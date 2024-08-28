#!/usr/bin/env python3

# divide aslevel_links.txt into multiple files such that each file contains a set of independent links
# that can be processed in parallel, e.g., no two lines in the same file share a common namespace
# source: gpt-4


import os
import sys


def read_input_file(file_path):
    ext_links = []
    with open(file_path, "r") as file:
        for line in file:
            cur_link = [part.strip() for part in line.split("\t")]
            # if one region name is None, replace it with IXP
            ext_links.append(
                (
                    cur_link[0]
                    + " "
                    + cur_link[1].replace("None", "IXP"),  # container 1
                    cur_link[3]
                    + " "
                    + cur_link[4].replace("None", "IXP"),  # container 2
                    cur_link[6],  # throughput
                    cur_link[7],  # delay
                    cur_link[8],  # buffer
                )
            )

    return ext_links


def compute_independent_links(data):
    # compute the independent link groups such that
    # each group contains a set of links that can be processed in parallel
    unique_container_groups = []
    independent_link_groups = []
    # find the first group that has not included any container in the current line
    for ctn_a, ctn_b, throughput, delay, buffer in data:
        can_join = False  # whether the current line can be joined to an existing group
        for ctn_grp_id, ctn_group in enumerate(unique_container_groups):
            if not (ctn_a in ctn_group or ctn_b in ctn_group):
                can_join = True
                ctn_group.add(ctn_a)
                ctn_group.add(ctn_b)
                independent_link_groups[ctn_grp_id].append(
                    (ctn_a, ctn_b, throughput, delay, buffer)
                )
                break
        if not can_join:
            # create a new group
            unique_container_groups.append({ctn_a, ctn_b})
            independent_link_groups.append([
                (ctn_a, ctn_b, throughput, delay, buffer)])

    return independent_link_groups


def write_output_files(link_groups, output_dir):
    # write the independent link groups to multiple files
    input_file_prefix = f"{output_dir}/aslevel_links"
    for i, link_group in enumerate(link_groups):
        with open(f"{input_file_prefix}_{i}.txt", "w") as file:
            for link in link_group:
                file.write("\t".join(link) + "\n")
            # delete the last newline character
            file.seek(file.tell() - 1)
            file.truncate()


def main(input_file, output_dir):
    ext_links = read_input_file(input_file)
    link_groups = compute_independent_links(ext_links)
    write_output_files(link_groups, output_dir)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 _compute_independent_ext_links.py <directory>")
        sys.exit(1)

    directory = sys.argv[1]
    input_file = f"{directory}/config/aslevel_links.txt"
    output_dir = f"{directory}/groups/aslevel_links/"
    os.makedirs(output_dir, exist_ok=True)

    main(input_file, output_dir)
