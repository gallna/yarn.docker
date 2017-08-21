#!/usr/bin/env bash

# Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
#
# Usage:
#   printf "prop1 val1 \n prop2 val2 \n" | $0 <pathname>
#   cat <<EOL | $0 yarn-site.xml
#   prop1 val1
#   prop2 val2
#   EOL

if [[ ! -f "${1}" ]]; then
  echo >&2 "Provided argument [${1}] is not a file"
  exit 2
fi
xml=$(mktemp --dry-run)
test -z "${UPDATE-}" && cp "${1}" "${xml}" || xml="$1"


# new_property <file> <property.name> <property.value>
function new_property() {
  xmlstarlet ed --inplace \
    -s '/configuration' -t elem -n "prop" \
    -s '/configuration/prop' -t elem -n "name" -v "$1" \
    -s '/configuration/prop' -t elem -n "value" -v "$2" \
    -r '/configuration/prop' -v 'property' "$xml"
}

# edit_property <file> <property.name> <property.value>
function edit_property() {
  xmlstarlet ed --inplace --var name "'$1'" \
    -u '//configuration/property[name = $name]/value' -v "$2" "$xml"
}
# get_property <file> <property.name>
function get_property() {
  xmlstarlet sel -t -m "//configuration/property[name = '$1']" -v 'value' "$xml"

}
# update_property <file> <property.name> <property.value>
function update_property() {
    get_property $1 >/dev/null && edit_property $1 $2 || new_property $1 $2
}

while read line; do
  test -z "$line" && continue || read name value <<< $line
  update_property $name $value
done

test -z "${UPDATE-}" && cat $xml && rm -f $xml
