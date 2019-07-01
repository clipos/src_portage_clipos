# Copyright © 2017 ANSSI. All rights reserved.
# Distributed under the terms of the GNU General Public License v2

# @ECLASS: clipos-product-info.eclass
# @BLURB: Helper eclass to set misc product information
# @DESCRIPTION:
# Instead of hardcoding product information such as product names in ebuilds,
# set them here once to enable derivatives to easy override given values in an
# eclass in an overlay.
# Values must match those in products/clipos/properties.toml.

clipos-product-info_get_shortname() {
	echo "clipos"
}

clipos-product-info_get_commonname() {
	echo "CLIP OS"
}

EXPORT_FUNCTIONS get_shortname get_commonname
