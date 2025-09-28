#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUTPUTS_DIR="${WORKSPACE_DIR}/outputs"
AGGREGATE_ROOT="${OUTPUTS_DIR}/librockchip_rk35xx"

source "${SCRIPT_DIR}/../common.sh"

reset_build_type_state

ensure_tools_available curl mktemp

DEFAULT_TARGET_CONFIGS=(
	"aarch64-linux-gnu-debug|aarch64-linux-gnu|Debug|linux"
	"aarch64-linux-gnu|aarch64-linux-gnu|Release|linux"
	"arm-linux-gnueabihf|arm-linux-gnueabihf|Release|linux"
	"aarch64-linux-android|aarch64-linux-android|Release|android"
	"arm-linux-android|arm-linux-android|Release|android"
)

DEPENDENCIES=(
	"libdrm"
	"rkrga"
	"rkmpp"
	"opencv"
	"ffmpeg-rockchip"
)

directory_has_contents() {
	local dir="$1"

	if [ ! -d "$dir" ]; then
		return 1
	fi

	local entry
	entry="$(find "$dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)"

	if [ -n "$entry" ]; then
		return 0
	fi

	return 1
}

declare -A RKNPU2_LIB_URLS=(
	["aarch64-linux-gnu"]="https://github.com/airockchip/rknn-toolkit2/blob/master/rknpu2/runtime/Linux/librknn_api/aarch64/librknnrt.so"
	["arm-linux-gnueabihf"]="https://github.com/airockchip/rknn-toolkit2/blob/master/rknpu2/runtime/Linux/librknn_api/armhf/librknnrt.so"
	["aarch64-linux-android"]="https://github.com/airockchip/rknn-toolkit2/blob/master/rknpu2/runtime/Android/librknn_api/arm64-v8a/librknnrt.so"
	["arm-linux-android"]="https://github.com/airockchip/rknn-toolkit2/blob/master/rknpu2/runtime/Android/librknn_api/armeabi-v7a/librknnrt.so"
)

RKNPU2_LINUX_HEADERS=(
	"https://github.com/airockchip/rknn-toolkit2/blob/master/rknpu2/runtime/Linux/librknn_api/include/rknn_api.h"
	"https://github.com/airockchip/rknn-toolkit2/blob/master/rknpu2/runtime/Linux/librknn_api/include/rknn_custom_op.h"
	"https://github.com/airockchip/rknn-toolkit2/blob/master/rknpu2/runtime/Linux/librknn_api/include/rknn_matmul_api.h"
)

RKNPU2_ANDROID_HEADERS=(
	"https://github.com/airockchip/rknn-toolkit2/blob/master/rknpu2/runtime/Android/librknn_api/include/rknn_api.h"
	"https://github.com/airockchip/rknn-toolkit2/blob/master/rknpu2/runtime/Android/librknn_api/include/rknn_custom_op.h"
	"https://github.com/airockchip/rknn-toolkit2/blob/master/rknpu2/runtime/Android/librknn_api/include/rknn_matmul_api.h"
)

convert_to_raw_url() {
	local url="$1"

	if [[ "$url" =~ ^https://github\.com/([^/]+)/([^/]+)/blob/(.+)$ ]]; then
		echo "https://raw.githubusercontent.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/${BASH_REMATCH[3]}"
	else
		echo "$url"
	fi
}

download_file_if_missing() {
	local url="$1"
	local destination="$2"

	if [ -f "$destination" ]; then
		log_info "File already exists, skipping download: $destination"
		return 0
	fi

	local raw_url
	raw_url="$(convert_to_raw_url "$url")"

	mkdir -p "$(dirname "$destination")"

	local tmp_file
	tmp_file="$(mktemp "${destination}.XXXXXX")"

	log_info "Downloading $(basename "$destination") from $raw_url"
	if ! curl -L --fail --show-error --silent "$raw_url" -o "$tmp_file"; then
		rm -f "$tmp_file"
		log_error "Failed to download $raw_url"
		return 1
	fi

	mv "$tmp_file" "$destination"
	log_success "Downloaded $(basename "$destination") to $(dirname "$destination")"
}

ensure_component_built() {
	local component="$1"
	local target_name="$2"
	local base_target="$3"
	local build_type="$4"

	local component_output_dir="${OUTPUTS_DIR}/${component}/${target_name}"

	if directory_has_contents "$component_output_dir"; then
		log_info "$component output found for $target_name"
		return 0
	fi

	if [ -d "$component_output_dir" ]; then
		log_warning "$component output directory exists but is empty for $target_name, rebuilding"
		rm -rf "$component_output_dir"
	fi

	local build_script="${WORKSPACE_DIR}/scripts/${component}/build.sh"

	if [ ! -f "$build_script" ]; then
		log_error "Build script not found for $component: $build_script"
		return 1
	fi

	if [ ! -x "$build_script" ]; then
		chmod +x "$build_script"
	fi

	log_warning "$component output missing for $target_name, invoking build script"

	if ! "$build_script" --build_type "$build_type" "$base_target"; then
		log_error "Failed to build $component for $base_target ($build_type)"
		return 1
	fi

	if ! directory_has_contents "$component_output_dir"; then
		log_error "Expected output directory not found after build: $component_output_dir"
		return 1
	fi

	log_success "$component built for $target_name"
}

sync_component_output() {
	local component="$1"
	local target_name="$2"

	local source_dir="${OUTPUTS_DIR}/${component}/${target_name}"
	local destination_dir="${AGGREGATE_ROOT}/${target_name}/${component}"

	if [ ! -d "$source_dir" ]; then
		log_error "Source directory missing for $component: $source_dir"
		return 1
	fi

	mkdir -p "${AGGREGATE_ROOT}/${target_name}"

	if [ -d "$destination_dir" ]; then
		rm -rf "$destination_dir"
	fi

	log_info "Copying $component artifacts for $target_name"
	cp -a "$source_dir" "$destination_dir"
}

ensure_rknpu2_assets() {
	local target_name="$1"
	local base_target="$2"
	local platform="$3"

	local bundle_root="${AGGREGATE_ROOT}/${target_name}/rknpu2"
	local lib_dest="${bundle_root}/lib/librknnrt.so"

	local lib_url="${RKNPU2_LIB_URLS[$base_target]:-}"
	if [ -z "$lib_url" ]; then
		log_warning "No rknpu2 library URL configured for $base_target, skipping"
	else
		download_file_if_missing "$lib_url" "$lib_dest"
	fi

	local include_dir="${bundle_root}/include"
	local header_urls=()

	if [ "$platform" = "android" ]; then
		header_urls=("${RKNPU2_ANDROID_HEADERS[@]}")
	else
		header_urls=("${RKNPU2_LINUX_HEADERS[@]}")
	fi

	local header_url
	for header_url in "${header_urls[@]}"; do
		local header_name
		header_name="$(basename "$header_url")"
		download_file_if_missing "$header_url" "${include_dir}/${header_name}"
	done
}

process_target() {
	local target_config="$1"

	IFS='|' read -r target_name base_target build_type platform <<< "$target_config"

	log_info "=============================="
	log_info "Processing target: $target_name (base: $base_target, type: $build_type)"

	mkdir -p "${AGGREGATE_ROOT}/${target_name}"

	local component
	for component in "${DEPENDENCIES[@]}"; do
		if ! ensure_component_built "$component" "$target_name" "$base_target" "$build_type"; then
			return 1
		fi

		if ! sync_component_output "$component" "$target_name"; then
			return 1
		fi
	done

	if ! ensure_rknpu2_assets "$target_name" "$base_target" "$platform"; then
		return 1
	fi

	log_success "Completed processing for $target_name"
}

select_target_configs() {
	local -n selected_configs_ref="$1"

	if [ "$#" -lt 1 ]; then
		log_error "select_target_configs requires array name as first argument"
		return 1
	fi

	shift

	if [ "$#" -eq 0 ]; then
		selected_configs_ref=("${DEFAULT_TARGET_CONFIGS[@]}")
		return 0
	fi

	local requested
	for requested in "$@"; do
		local matched_config=""
		local config
		for config in "${DEFAULT_TARGET_CONFIGS[@]}"; do
			IFS='|' read -r target_name _ <<< "$config"
			if [ "$requested" = "$target_name" ]; then
				matched_config="$config"
				break
			fi
		done

		if [ -z "$matched_config" ]; then
			log_error "Unsupported target requested: $requested"
			return 1
		fi

		local already_present="false"
		local existing
		for existing in "${selected_configs_ref[@]:-}"; do
			if [ "$existing" = "$matched_config" ]; then
				already_present="true"
				break
			fi
		done

		if [ "$already_present" = "false" ]; then
			selected_configs_ref+=("$matched_config")
		fi
	done
}

main() {
	mkdir -p "$AGGREGATE_ROOT"

	local selected_configs=()
	if ! select_target_configs selected_configs "$@"; then
		exit 1
	fi

	local config
	for config in "${selected_configs[@]}"; do
		if ! process_target "$config"; then
			log_error "Failed processing target configuration: $config"
			exit 1
		fi
	done

	log_success "All requested targets processed successfully"
}

main "$@"
