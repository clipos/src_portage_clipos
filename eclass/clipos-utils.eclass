# Copyright © 2020 ANSSI. All rights reserved.
# Distributed under the terms of the GNU General Public License v2

# @ECLASS: clipos-utils.eclass
# @BLURB: Handy eclass with various helpers
# @DESCRIPTION: This eclass contains various helpers intended for easier
# writing of CLIP OS ebuilds.

inherit eutils

# Replace placeholders (in the form "@VARIABLE_NAME@" where "VARIABLE_NAME" is
# the name of an exported environment variable) in a given file. This
# replacement is "virtually" made in-place.
# NB: variables names must verify this regexp '^[a-zA-Z\_][a-zA-Z0-9\_]*$'
# (POSIX environment variable names format).
clipos-utils_replace_placeholders() {
    local file="${1:?replace_placeholders <file>}"
    [[ -r "$file" && -w "$file" ]] || return 1

    local tempfile="$(emktemp)"

    gawk '
        {
            delete res
            while(match($0, /@([a-zA-Z\_][a-zA-Z0-9\_]*)@/, res)) {
                placeholder = res[0]
                varname = res[1]
                if (! (varname in ENVIRON)) {
                    print "\""varname"\" has not been found in the environment variables." > "/dev/stderr"
                    exit 1
                }
                value = ENVIRON[varname]
                gsub(placeholder, value)
            }
            print
        }' "$file" >| "$tempfile" \
            || { rm -f "$tempfile"; return 3; }

    cat "$tempfile" >| "$file" || { rm -f "$tempfile"; return 4; }
    rm -f "$tempfile"
}

EXPORT_FUNCTIONS replace_placeholders
