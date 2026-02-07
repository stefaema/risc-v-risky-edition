OUT = "svg/parsed_svg.svg"

component_to_group_id = {}
pattern= "inkscape:label=\""
def parse_svg(input_path):
    with open(input_path, 'r', encoding='utf-8') as f:
        svg_content = f.read()
    
    lines_where_pattern_appears = [i for i, line in enumerate(svg_content.splitlines()) if pattern in line]
    print(f"Found {len(lines_where_pattern_appears)} occurrences of pattern '{pattern}' in SVG.")
    # Extract all labels text first:
    for line in lines_where_pattern_appears:
        line_content = svg_content.splitlines()[line]
        label_start = line_content.find(pattern) + len(pattern)
        label_end = line_content.find('"', label_start)
        label_text = line_content[label_start:label_end]
        print(f"Extracted label: '{label_text}' from line {line}")
        # Group is either in the line before or the previous two lines, we check both:
        group_id = None
        for offset in range(1, 3):
            if line - offset >= 0:
                prev_line = svg_content.splitlines()[line - offset]
                if 'id="' in prev_line:
                    id_start = prev_line.find('id="') + len('id="')
                    id_end = prev_line.find('"', id_start)
                    group_id = prev_line[id_start:id_end]
                    print(f"Found group ID: '{group_id}' for label '{label_text}' in line {line - offset}")
                    component_to_group_id[label_text] = group_id
                    break

    # For demonstration, we will just print the mapping
    print("Component to Group ID Mapping:")
    for component, group_id in component_to_group_id.items():
        print(f"Component: '{component}' -> Group ID: '{group_id}'")


if __name__ == "__main__":
    parse_svg("svg/risc-v-diagram.svg")
