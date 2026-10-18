extends RefCounted
## Loads a Spectator presentation and verifies it against its manifest.
##
## Each presentation file is read once; its size and SHA-256 are checked
## against manifest.json before the same bytes are parsed, so the viewer never
## renders a file the manifest does not vouch for.
##
## Manifest versions are handled explicitly, never by guessing:
## * version 1 - Spectator's own pinned prototype exporter
##   (exporter/spectator_export.py): provenance teaching_demo or showcase_match,
##   bound to the pinned Bytefray commit;
## * version 2 - Bytefray's production exporter (`bytefray spectator export`,
##   battle_client.spectator_export): provenance bytefray_match, a normal
##   completed match verified by Bytefray itself.
## Both describe the same broadcast/agent_a documents (schema version 1). Any
## other manifest version is rejected as unsupported.

const MANIFEST_SCHEMA := "bytefray.spectator.manifest"
const SCHEMA_VERSION := 1  # the broadcast/agent_a document version
const MANIFEST_VERSIONS := [1, 2]
const SCHEMAS := {
	"broadcast": "bytefray.spectator.broadcast",
	"agent_a": "bytefray.spectator.agent_view",
}
const REQUIRED_VERIFICATION := [
	"artifact_pair_consistent",
	"exchange_reconstructed",
	"outcome_verified",
	"agent_view_allowlist_checked",
]
const PROVENANCES := ["teaching_demo", "showcase_match"]
# Version 2: what Bytefray's production exporter must have verified.
const PRODUCTION_PROVENANCE := "bytefray_match"
const PRODUCTION_EXPORTER := "battle_client.spectator_export"
const PRODUCTION_VERIFICATION := ["result_replay_preflight", "sources_unchanged"]


static func manifest_version(manifest: Dictionary) -> int:
	return int(manifest.get("schema_version", 0))


static func load_manifest(dir: String) -> Dictionary:
	var path := dir.path_join("manifest.json")
	if not FileAccess.file_exists(path):
		return {"error": "manifest.json not found in %s" % dir}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"error": "manifest.json is not a JSON object"}
	var manifest: Dictionary = parsed
	var version: Variant = manifest.get("schema_version")
	if (
		manifest.get("schema") != MANIFEST_SCHEMA
		or typeof(version) not in [TYPE_INT, TYPE_FLOAT]
		or float(version) != floorf(float(version))
		or not MANIFEST_VERSIONS.has(int(version))
	):
		return {"error": "unsupported manifest schema"}
	var verification: Variant = manifest.get("verification", {})
	if typeof(verification) != TYPE_DICTIONARY:
		return {"error": "manifest does not record a verified match"}
	for key in REQUIRED_VERIFICATION:
		if verification.get(key) != true:
			return {"error": "manifest does not record a verified match (%s)" % key}
	var provenance: Variant = verification.get("provenance")
	var problem := _check_v1(manifest, provenance) if int(version) == 1 else _check_v2(manifest, provenance)
	if problem != "":
		return {"error": problem}
	var match_info: Variant = manifest.get("match", {})
	if typeof(match_info) != TYPE_DICTIONARY:
		return {"error": "manifest records no match"}
	var tick_limit: Variant = match_info.get("tick_limit")
	if typeof(tick_limit) not in [TYPE_INT, TYPE_FLOAT] or int(tick_limit) < 1:
		return {"error": "manifest records no tick limit"}
	return {"manifest": manifest}


static func _check_v1(manifest: Dictionary, provenance: Variant) -> String:
	if not PROVENANCES.has(provenance):
		return "manifest records an unknown provenance"
	var verification: Dictionary = manifest["verification"]
	if provenance == "teaching_demo" and verification.get("teaching_complete") != true:
		return "manifest does not record a verified teaching demonstration"
	var bytefray: Variant = manifest.get("bytefray", {})
	if typeof(bytefray) != TYPE_DICTIONARY or typeof(bytefray.get("commit")) != TYPE_STRING:
		return "manifest records no Bytefray source"
	return ""


static func _check_v2(manifest: Dictionary, provenance: Variant) -> String:
	if provenance != PRODUCTION_PROVENANCE:
		return "manifest records an unknown provenance"
	var verification: Dictionary = manifest["verification"]
	for key in PRODUCTION_VERIFICATION:
		if verification.get(key) != true:
			return "manifest does not record a verified match (%s)" % key
	var exporter: Variant = manifest.get("exporter", {})
	if typeof(exporter) != TYPE_DICTIONARY or exporter.get("name") != PRODUCTION_EXPORTER:
		return "manifest records an unknown exporter"
	var bytefray: Variant = manifest.get("bytefray", {})
	if typeof(bytefray) != TYPE_DICTIONARY or typeof(bytefray.get("version")) != TYPE_STRING or String(bytefray["version"]).is_empty():
		return "manifest records no Bytefray version"
	return ""


## Short source identity for the footer: the pinned commit (version 1) or the
## exporting Bytefray version (version 2).
static func source_label(manifest: Dictionary) -> String:
	if manifest_version(manifest) == 1:
		return String(manifest["bytefray"]["commit"]).substr(0, 7)
	return String(manifest["bytefray"]["version"])


static func sha256_hex(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func load_presentation(dir: String, manifest: Dictionary, key: String) -> Dictionary:
	if not SCHEMAS.has(key):
		return {"error": "unknown presentation %s" % key}
	var presentation: Variant = manifest.get("presentation", {})
	if typeof(presentation) != TYPE_DICTIONARY:
		return {"error": "manifest lists no %s presentation" % key}
	var entry_value: Variant = presentation.get(key, {})
	if typeof(entry_value) != TYPE_DICTIONARY or (entry_value as Dictionary).is_empty():
		return {"error": "manifest lists no %s presentation" % key}
	var entry: Dictionary = entry_value
	var name := String(entry.get("path", ""))
	if name.is_empty() or name.contains("/") or name.contains("\\") or name.contains(".."):
		return {"error": "unsafe presentation path"}
	if manifest_version(manifest) >= 2 and int(entry.get("schema_version", 0)) != SCHEMA_VERSION:
		return {"error": "%s has an unexpected schema" % name}
	var path := dir.path_join(name)
	if not FileAccess.file_exists(path):
		return {"error": "%s is missing" % name}
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() != int(entry.get("bytes", -1)):
		return {"error": "%s size does not match the manifest" % name}
	if sha256_hex(bytes) != String(entry.get("sha256", "")):
		return {"error": "%s SHA-256 does not match the manifest" % name}
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_ascii())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"error": "%s is not a JSON object" % name}
	var document: Dictionary = parsed
	if document.get("schema") != SCHEMAS[key] or int(document.get("schema_version", 0)) != SCHEMA_VERSION:
		return {"error": "%s has an unexpected schema" % name}
	if (document.get("frames", []) as Array).size() != int(entry.get("frames", -1)):
		return {"error": "%s frame count does not match the manifest" % name}
	return {"document": document}
