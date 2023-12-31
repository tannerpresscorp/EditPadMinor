#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift open source project
##
## Copyright (c) 2022 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See http://swift.org/LICENSE.txt for license information
## See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

set -eu
here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
contributor_list=$( cd "$here"/.. && git shortlog -es | cut -f2 )
filtered_hashes=$( cat "$here/../.mailfilter" | grep -E '^[a-z0-9]+$' | sort )

NL=$'\n'

contributors=''
while IFS= read -r line; do
	hashed="$(echo -n "$line" | shasum | head -c 40)"
	found_hash=$(comm -12 <(echo "$hashed") <(echo "$filtered_hashes"))
	if [ ! -z "$found_hash" ]; then
		continue
	fi
	contributors="${contributors}- $line$NL"
done <<< "$contributor_list"

cat > "$here/../CONTRIBUTORS.txt" <<- EOF
	For the purpose of tracking copyright, this is the list of individuals and
	organizations who have contributed to Swift Package Manager.

	For employees of an organization/company where the copyright of work done
	by employees of that company is held by the company itself, only the company
	needs to be listed here.

	## COPYRIGHT HOLDERS

	- Apple Inc. (all contributors with '@apple.com')

	### Contributors

	$contributors
	**Updating this list**

	Please do not edit this file manually. It is generated using \`./Utilities/generate_contributors_list.sh\`. If a name is misspelled or appearing multiple times: add an entry in \`./.mailmap\`
EOF
