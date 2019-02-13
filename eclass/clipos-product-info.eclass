# Copyright © 2017 ANSSI. All rights reserved.
# Distributed under the terms of the GNU General Public License v2

# @ECLASS: clipos-product-info.eclass
# @BLURB: helper eclass for obtaining product information
# @DESCRIPTION:
# Instead of hardcoding product information such as product names in ebuilds,
# extract them from the product.toml file through environment variables.

# Extract a key from the current product properties passed through the
# environment variable set CURRENT_PRODUCT_PROPERTIES and
# CURRENT_PRODUCT_PROPERTY_*. These environment variables are produced by the
# cosmk utility which has serialized the "properties.toml" file beforehand.
get_product_property() {
	local key="${1}"
	local k i=0 found=0
	for k in ${CURRENT_PRODUCT_PROPERTIES:-}; do
		if [[ "$k" == "$key" ]]; then
			found=1
			break;
		fi
		let i++ || true
	done
	if [[ "$found" -eq 0 ]]; then
		# key not found
		echo >&2 "get_product_property(): could not found product property \"${key}\""
		return 1
	else
		# key has been found
		local varname="CURRENT_PRODUCT_PROPERTY_${i}"
		echo "${!varname}"
	fi
}

# Extract product short name
clipos-product-info_get_shortname() {
	echo "$(get_product_property 'short_name')"
}

# Extract product common name
clipos-product-info_get_commonname() {
	echo "$(get_product_property 'common_name')"
}

EXPORT_FUNCTIONS get_shortname get_commonname
