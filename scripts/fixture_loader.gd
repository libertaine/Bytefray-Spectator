extends RefCounted
## Loads a Spectator presentation fixture and verifies it against its manifest.
##
## Each presentation file is read once; its size and SHA-256 are checked
## against manifest.json before the same bytes are parsed, so the viewer never
## renders a file the manifest does not vouch for.

const MANIFEST_SCHEMA := "bytefray.spectator.manifest"
const SCHEMA_VERSION := 1
const SCHEMAS := {
	"broadcast": "bytefray.spectator.broadcast",
	"agent_a": "bytefray.spectator.agent_view",
}
const REQUIRED_VERIFICATION := [
	"artifact_pair_consistent",
	"exchange_reconstructed",
	"teaching_complete",
	"agent_view_allowlist_checked",
]


static func load_manifest(dir: String) -> Dictionary:
	var path := dir.path_join("manifest.json")
	if not FileAccess.file_exists(path):
		return {"error": "manifest.json not found in %s" % dir}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"error": "manifest.json is not a JSON object"}
	var manifest: Dictionary = parsed
	if manifest.get("schema") != MANIFEST_SCHEMA or int(manifest.get("schema_version", 0)) != SCHEMA_VERSION:
		return {"error": "unsupported manifest schema"}
	var verification: Dictionary = manifest.get("verification", {})
	for key in REQUIRED_VERIFICATION:
		if verification.get(key) != true:
			return {"error": "manifest does not record a verified match (%s)" % key}
	return {"manifest": manifest}


static func sha256_hex(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func load_presentation(dir: String, manifest: Dictionary, key: String) -> Dictionary:
	if not SCHEMAS.has(key):
		return {"error": "unknown presentation %s" % key}
	var entry: Dictionary = manifest.get("presentation", {}).get(key, {})
	if entry.is_empty():
		return {"error": "manifest lists no %s presentation" % key}
	var name := String(entry.get("path", ""))
	if name.is_empty() or name.contains("/") or name.contains("\\") or name.contains(".."):
		return {"error": "unsafe presentation path"}
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
