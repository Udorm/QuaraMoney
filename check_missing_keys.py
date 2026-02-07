import re

def parse_strings_file(file_path):
    keys = set()
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
        # Regex to match "key" = "value"; ignoring comments
        # This is a simple regex and might need refinement for complex cases
        # pattern = r'^\s*"([^"]+)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;'
        # multiline handling is not strictly needed if keys are consistent
        # Let's iterate line by line to be safer with comments
        
        # Actually, let's just find all "key" = "..." patterns
        # We need to be careful about matching comments.
        # But simple regex for "key" = should work for identification
        
        matches = re.findall(r'^\s*"([^"]+)"\s*=', content, re.MULTILINE)
        return set(matches)

en_path = "/Users/udormphon/Developer/QuaraMoney/QuaraMoney/en.lproj/Localizable.strings"
km_path = "/Users/udormphon/Developer/QuaraMoney/QuaraMoney/km.lproj/Localizable.strings"

en_keys = parse_strings_file(en_path)
km_keys = parse_strings_file(km_path)

missing_in_km = en_keys - km_keys
missing_in_en = km_keys - en_keys

print("Missing in KM:")
for k in sorted(missing_in_km):
    print(k)

print("\nMissing in EN:")
for k in sorted(missing_in_en):
    print(k)
