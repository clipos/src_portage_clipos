# Copyright © 2019 ANSSI. All rights reserved.
# Distributed under the terms of the GNU General Public License v2

# @ECLASS: clipos-kernel.eclass
# @MAINTAINER:
# ANSSI/CLIP OS Developers <clipos@ssi.gouv.fr>
# @BLURB: eclass for common functions/metadata regarding the CLIP OS Kernel
# @SUPPORTED_EAPIS: 6 7
# @DESCRIPTION:
# This eclass is inteded to avoid code duplication between all the eclass that
# handle the CLIP OS kernel (e.g. sys-kernel/clipos-kernel,
# sys-kernel/clipos-kernel-sources et al.).

case "${EAPI:-0}" in
    0|1|2|3|4|5)
        die "Unsupported EAPI=${EAPI:-0} (too old) for ${ECLASS}"
        ;;
    6|7)
        ;;
    *)
        die "Unsupported EAPI=${EAPI} (unknown) for ${ECLASS}"
        ;;
esac

# This eclass is reserved for use by "sys-kernel/clipos-kernel*" atoms:
if [[ "${CATEGORY}" != 'sys-kernel' ||
      ! "${PN}" =~ ^clipos-kernel(-[a-z]+)?$ ]]; then
	die "\"${ECLASS}\" eclass is reserved for use by \"sys-kernel/clipos-kernel*\" ebuilds."
fi

LICENSE="GPL-2"
SLOT="0"
IUSE="ipv6 selinux"
IUSE+=" clipos_instrumentations_debuggable-kernel"
IUSE+=" clipos_instrumentations_soften-kernel-configuration"

CROS_WORKON_PROJECT=(
	'external/linux'                  # Linux kernel
	'platform/config-linux-hardware'  # Product's hardware configurations
)
CROS_WORKON_DESTDIR=(
	"${S}"
	"${S}/hardware"
)
case "${PVR:-0}" in
	5.6.16)
		CROS_WORKON_COMMIT=(
			'6218caf5ac6d0530e45af309713a2b16b78e68d6' # v5.6.16-24412-g6218caf5ac6d
			'330c7482ce19bb5ee596d29fb535bb337cea5cf6' # head of master branch
		)
		;;
	9999)
		# Do nothing and leave cros-workon eclass work with the current
		# state of the Git repositories defined in the
		# CROS_WORKON_PROJECT array.
		;;
	*)
		die "Unknown CLIP OS kernel version (${PV:-0}) by \"${ECLASS}\" eclass"
		;;
esac
# cros-workon eclass inheritage will inherit the proper src_unpack functions
inherit cros-workon

# To get a default name to set as hostname
inherit clipos-product-info

inherit eutils   # required for emktemp

# Disable standard env flags for kernel compiles
CFLAGS=""
ASFLAGS=""
LDFLAGS=""
ARCH=${ARCH#~}
ARCH=${ARCH/x86/i386}
ARCH=${ARCH/amd64/x86_64}

RDEPEND=""
DEPEND="${RDEPEND}
	app-arch/lz4
	sys-devel/bc
	sys-apps/net-tools
"
if [[ "${PN}" == 'clipos-kernel' ]]; then
	DEPEND+="
		sys-apps/kmod[lzma]
		sys-kernel/linux-firmware
		virtual/libelf
	"
fi

clipos-kernel_localversion() {
	local localversion=''
	if [[ "${PR}" != "r0" ]]; then
		localversion+="-${PR}"
	fi
	localversion+="-$(get_shortname)"
	local iuse_item=''
	for iuse_item in ${IUSE:-}; do
		if [[ "${iuse_item#+}" =~ ^clipos_instrumentations_ ]] && use "${iuse_item#+}"; then
			localversion+="+instrumented"
			break  # no need to continue if we found an instrumentation USE flag
		fi
	done
	echo "${localversion}"
}

clipos-kernel_compute_configuration() {
	local configsets=(
		basic
		boards
		cpu/intel
		cpu/x86_64
		graphics
		kvm_guest
		kvm_host
		misc_drivers
		net/basic
		net/ipsec
		net/netfilter
		net/netfilter_gw
		sound
		security/basic
		feature/linux-hardened
		)
	if use clipos_instrumentations_debuggable-kernel; then
		configsets+=(debug)
	fi
	if use ipv6; then
		configsets+=(
			net/ipv6
			net/ipsec_ipv6
			net/netfilter_ipv6
			net/netfilter_gw_ipv6
		)
	fi
	if use selinux; then
		configsets+=( security/selinux )
	fi

	# "make-config.sh" expects some environment variables to process the
	# configsets, do not forget them:
	CONFIGDIR="${CROS_WORKON_DESTDIR[1]}" S="$S" ARCH="$ARCH" \
		DEBUG=$(usex clipos_instrumentations_debuggable-kernel 1 0) \
		"${CROS_WORKON_DESTDIR[1]}/make-config.sh" "${configsets[@]}" \
			|| die "Failed to generate kernel configuration"

	# Workaround to prevent '+' sign from being appended to the local version
	> "${S}/.scmversion"

	# Append revision and distro name to kernel local version
	clipos-kernel_set_opt "CONFIG_LOCALVERSION" "\"$(clipos-kernel_localversion)\""

	# Set Linux Security Modules stacking
	local lsm_ordered_list="yama"
	if use selinux ; then
		lsm_ordered_list+=",selinux"
	fi
	clipos-kernel_set_opt "CONFIG_LSM" "\"$lsm_ordered_list\""

	# (Un)set some Kconfig options (that we cannot handle with the debug
	# configset because they are already set in other configsets) to ease
	# debugging
	if use clipos_instrumentations_debuggable-kernel; then
		ewarn "Setting DEBUG options"
		clipos-kernel_unset_opt "CONFIG_PANIC_ON_OOPS"
		clipos-kernel_set_opt "CONFIG_PANIC_TIMEOUT" 0
	fi
}

# Take care to include the surrounding quotes if you want your value to be
# considered as a string or an hexadecimal value (see Kconfig types). This
# function won't surround automagically the quotes if your values needs to be
# quoted.
clipos-kernel_set_opt() {
	local optname="${1:?optname argument is needed}"
	local optval="${2?optval argument is needed}"

	# Avoid handling configuration values with special characters in them
	# (see regexp below for definition of "special chars"). This safety
	# measure is explained by the fact that ${optval} is part of a
	# "substitute" sed command below and potential special chars may
	# trigger unexpected behavior of sed when inserting the requested
	# value. Better safe than sorry.
	if [[ ! "${optval:-}" =~ ^[a-zA-Z0-9\ \.\_\/\"\,\+\-]*$ ]]; then
		eerror "clipos-kernel_set_opt() do not handle kernel configuration value setting"
		eerror "with special chars in them."
		eerror "  Option name: ${optname}"
		eerror "  Option value to set: ${optval:-}"
		die
	fi

	einfo "Setting option ${optname} to ${optval}."
	sed -i -e "s/^${optname}=.*/${optname}=${optval}/" "${S}/.config"
	sed -i -e "s/^# ${optname} is not set.*/${optname}=${optval}/" "${S}/.config"
	grep -qE "^${optname}=${optval}" "${S}/.config" \
		|| echo "${optname}=${optval}" >> "${S}/.config"
}

clipos-kernel_unset_opt() {
	local optnamepat="${1:?optnamepat argument is needed}"
	local optmatch
	local found=0

	while read optmatch; do
		let found++ || true
		if [[ ${optmatch} == ${optnamepat} ]]; then
			einfo "Unsetting option ${optmatch}"
		else
			einfo "Unsetting option ${optmatch} matching pattern ${optnamepat}"
		fi
		sed -i -r "s/^${optmatch}=.*/# ${optmatch} is not set/" "${S}/.config"
	done < <(sed -n -r "s/^(${optnamepat})=.*/\1/p" "${S}/.config")

	if [[ ${found} -eq 0 ]]; then
		# Be sure to unset invisible option too
		einfo "Unsetting option ${optnamepat}"
		echo "# ${optnamepat} is not set" >> "${S}/.config"
	fi
}

clipos-kernel_compile_kernel() {
	make ${MAKEOPTS} ARCH="${ARCH}" all \
		|| die "Kernel compilation failed."

	local kernel_versionstring_compiled
	kernel_versionstring_compiled="$(make -s kernelrelease)"

	local expected_kernel_versionstring
	expected_kernel_versionstring="${PV}$(clipos-kernel_localversion)"

	# Check that the kernel versionstring compiled is the same as the one
	# we expect and fail miserably otherwise. This is a safety measure
	# because if those two values differ, then there may be somewhere a
	# package version mismanagement.
	if [[ "${PV}" != "9999" &&
	      "${kernel_versionstring_compiled}" != "${expected_kernel_versionstring}" ]]; then
		eerror "CLIP OS kernel version string does not match the version string produced"
		eerror "by the kernel compilation."
		eerror "  CLIP OS kernel version string expected: ${expected_kernel_versionstring}"
		eerror "  Kernel version string compiled: ${kernel_versionstring_compiled}"
		die "Aborting."
	fi
}

clipos-kernel_compile_modules() {
	make ${MAKEOPTS} ARCH="${ARCH}" modules_prepare \
		|| die "Kernel modules compilation failed."
}

clipos-kernel_install_kernel() {
	local kernel_versionstring_compiled
	kernel_versionstring_compiled="$(make -s kernelrelease)"

	# Install kernel image, System.map and configuration in /boot
	# (dracut will only grab the kernel image anyway)
	insinto "/boot"
	newins arch/x86/boot/bzImage "vmlinuz-${kernel_versionstring_compiled}"
	dosym "vmlinuz-${kernel_versionstring_compiled}" "/boot/vmlinuz"
	newins System.map "System.map-${kernel_versionstring_compiled}"
	newins .config "config-${kernel_versionstring_compiled}"
}

clipos-kernel_install_modules() {
	local kernel_versionstring_compiled
	kernel_versionstring_compiled="$(make -s kernelrelease)"

	# Install modules
	make ${MAKEOPTS} INSTALL_MOD_PATH="${D}" modules_install

	# By default (i.e. by using modules_install from the kernel's Makefile),
	# these 2 nodes are symlinks to the kernel sources directory. But this
	# directory won't exist outside of the temporary emerge working directory
	# and these 2 symlinks will be broken after install.
	rm -f "${D}/lib/modules/${kernel_versionstring_compiled}/build" \
		"${D}/lib/modules/${kernel_versionstring_compiled}/source"
}

clipos-kernel_install_sources() {
	into "/usr/src"
	mv "${S%%/}" "${ED}/usr/src/linux-${PV}$(clipos-kernel_localversion)"
	rm -rf "${ED}/usr/src/linux-${PV}$(clipos-kernel_localversion)/.git"
	dosym "linux-${PV}$(clipos-kernel_localversion)" "/usr/src/linux"
}

clipos-kernel_install_firmwares() {
	# Install hardware profiles and firmware files
	local hardware_repo_checkout="$(basename -- "${CROS_WORKON_DESTDIR[1]}")"
	local profile name core nb_main=0 nb_extra=0
	local firmwares_list="$(emktemp)"

	einfo "Installing hardware profiles and firmware files"

	for profile in "$hardware_repo_checkout/profiles"/* ; do
		[[ -d "$profile" ]] || continue
		insinto "/usr/share/$profile" && doins "$profile/modules"
		dodir "/usr/share/$profile/firmware"
		name="$(basename -- "$profile")"
		core="${name//+}"
		core="${core//-}"
		if [[ "$name" != "$core" ]]; then
			let "nb_extra++" || :
		else
			let "nb_main++" || :
		fi
		[[ -f "$profile/firmwares" ]] || continue
		while read firmware; do
			echo "$firmware" >> "$firmwares_list"
			dosym "/usr/share/$hardware_repo_checkout/firmware/$firmware" \
				"/usr/share/$profile/firmware/$firmware"
		done < "$profile/firmwares"
	done
	einfo "Installed ${nb_main} main configurations and ${nb_extra} derivatives"

	for firmware in $(sort -u "$firmwares_list"); do
		if [[ -f "/lib/firmware/$firmware" ]]; then
			local fw_dst_dir="/usr/share/$hardware_repo_checkout/firmware/$(dirname -- "$firmware")"
			insinto "$fw_dst_dir"
			doins "/lib/firmware/$firmware"
			if [[ -h "/lib/firmware/$firmware" ]]; then
				local relative_link_target="$(readlink -- "/lib/firmware/$firmware")"
				insinto "$fw_dst_dir/$(dirname -- "$relative_link_target")"
				doins "$(dirname -- "/lib/firmware/$firmware")/$relative_link_target"
			fi
		else
			eerror "Could not find firmware $firmware"
			die
		fi
	done
	rm "$firmwares_list"
}

clipos-kernel_install_sysctls() {
	# Install sysctl configuration files
	local hardware_repo_checkout="$(basename -- "${CROS_WORKON_DESTDIR[1]}")"
	local sysctls_configuration_dir="/etc/sysctl.d"

	einfo "Installing sysctl configuration files"

	diropts -o 0 -g 0 -m 0755
	dodir "$sysctls_configuration_dir"
	insinto "$sysctls_configuration_dir"
	insopts -o 0 -g 0 -m 0644
	doins "$hardware_repo_checkout/sysctls"/50-*.conf

	# The 'ipsec' configset pulls CONFIG_IPV6 since CONFIG_XFRM_INTERFACE
	# depends on it, therefore let's disable IPv6 at runtime if needed
	if ! use ipv6; then
		doins "$hardware_repo_checkout/sysctls/60-ipv6_disable.conf"
	fi

	if use clipos_instrumentations_soften-kernel-configuration; then
		einfo "Loosening some sysctls due to instrumentation"

		sed -i "/^kernel\.modules_disabled\s*=\s*1$/d" \
			"$D/$sysctls_configuration_dir/50-kernel.conf"
		sed -i "s/^\(kernel\.kptr_restrict\)\s*=\s*[0-2]$/\1 = 0/" \
			"$D/$sysctls_configuration_dir/50-kernel.conf"
		sed -i "s/^\(kernel\.yama.ptrace_scope\)\s*=\s*[0-3]$/\1 = 0/" \
			"$D/$sysctls_configuration_dir/50-kernel.conf"
	fi
}

# vim: set ts=8 sts=8 sw=8 noet tw=79:
