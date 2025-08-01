#!/usr/bin/env bash

# container-use installer script
# Downloads and installs the appropriate container-use binary for your system

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO="dagger/container-use"
BINARY_NAME="container-use"
INSTALL_DIR=""

# Helper functions
log_info() {
    printf "${BLUE}ℹ️  %s${NC}\n" "$1"
}

log_success() {
    printf "${GREEN}✅ %s${NC}\n" "$1"
}

log_warning() {
    printf "${YELLOW}⚠️  %s${NC}\n" "$1"
}

log_error() {
    printf "${RED}❌ %s${NC}\n" "$1"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."

    if ! command_exists docker; then
        log_error "Docker is required but not installed."
        log_info "Please install Docker from: https://docs.docker.com/get-started/get-docker/"
        exit 1
    fi

    if ! command_exists git; then
        log_error "Git is required but not installed."
        log_info "Please install Git from: https://git-scm.com/downloads"
        exit 1
    fi
}

# Detect operating system
detect_os() {
    local os
    case "$(uname -s)" in
        Linux*)     os="linux";;
        Darwin*)    os="darwin";;
        CYGWIN*|MINGW32*|MSYS*|MINGW*)
            log_error "Windows is not supported"
            log_info "container-use uses Unix syscalls and requires Linux or macOS"
            exit 1;;
        *)
            log_error "Unsupported operating system: $(uname -s)"
            exit 1;;
    esac
    echo "$os"
}

# Detect architecture
detect_arch() {
    local arch
    case "$(uname -m)" in
        x86_64|amd64)   arch="amd64";;
        arm64|aarch64)  arch="arm64";;
        *)
            log_error "Unsupported architecture: $(uname -m)"
            exit 1;;
    esac
    echo "$arch"
}



# Find the best installation directory
find_install_dir() {
    local install_dir="${BIN_DIR:-$HOME/.local/bin}"

    # Create the directory if it doesn't exist
    mkdir -p "$install_dir"

    # Check if it's writable
    if [ ! -w "$install_dir" ]; then
        log_error "$install_dir is not a writable directory"
        exit 1
    fi

    echo "$install_dir"
}

# Get the latest release version
get_latest_version() {
    curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

# Show shell completion setup instructions
show_completion_instructions() {
    local binary="$1"

    log_info "To enable shell completions:"
    echo ""
    echo "  # For container-use command:"
    echo "  $binary completion bash > /usr/local/etc/bash_completion.d/container-use"
    echo "  $binary completion zsh > /usr/local/share/zsh/site-functions/_container-use"
    echo "  $binary completion fish > ~/.config/fish/completions/container-use.fish"
    echo ""
    echo "  # For cu command:"
    echo "  $binary completion --command-name=cu bash > /usr/local/etc/bash_completion.d/cu"
    echo "  $binary completion --command-name=cu zsh > /usr/local/share/zsh/site-functions/_cu"
    echo "  $binary completion --command-name=cu fish > ~/.config/fish/completions/cu.fish"
}

# Verify checksum of downloaded file
verify_checksum() {
    local archive_file="$1"
    local archive_name="$2"
    local version="$3"

    log_info "Verifying checksum..."

    # Download checksums file
    local checksums_url="https://github.com/$REPO/releases/download/$version/checksums.txt"
    local checksums_file="$(dirname "$archive_file")/checksums.txt"

    curl -s -L -o "$checksums_file" "$checksums_url"
    if [ ! -f "$checksums_file" ]; then
        log_error "Failed to download checksums file"
        return 1
    fi

    # Extract expected checksum for our file
    local expected_checksum=$(grep "$(basename "$archive_file")" "$checksums_file" | cut -d' ' -f1)
    if [ -z "$expected_checksum" ]; then
        log_error "Checksum not found for $(basename "$archive_file")"
        return 1
    fi

    # Calculate actual checksum
    local actual_checksum
    if command_exists sha256sum; then
        actual_checksum=$(sha256sum "$archive_file" | cut -d' ' -f1)
    elif command_exists shasum; then
        actual_checksum=$(shasum -a 256 "$archive_file" | cut -d' ' -f1)
    else
        log_warning "No SHA256 tool found, skipping checksum verification"
        return 0
    fi

    # Compare checksums
    if [ "$actual_checksum" = "$expected_checksum" ]; then
        log_success "Checksum verified"
        return 0
    else
        log_error "Checksum verification failed!"
        log_error "Expected: $expected_checksum"
        log_error "Actual:   $actual_checksum"
        return 1
    fi
}

# Download and extract binary
download_and_install() {
    local os="$1"
    local arch="$2"
    local version="$3"
    local install_dir="$4"

    local archive_name="container-use_${version}_${os}_${arch}"
    local extension="tar.gz"

    local download_url="https://github.com/$REPO/releases/download/$version/${archive_name}.${extension}"
    local temp_dir=$(mktemp -d)
    local archive_file="$temp_dir/${archive_name}.${extension}"

    log_info "Downloading $BINARY_NAME $version for $os/$arch..."

    curl -L -o "$archive_file" "$download_url"

    if [ ! -f "$archive_file" ]; then
        log_error "Failed to download $download_url"
        exit 1
    fi

    # Verify checksum
    if ! verify_checksum "$archive_file" "$archive_name" "$version"; then
        log_error "Checksum verification failed, aborting installation"
        exit 1
    fi

    log_info "Extracting archive..."

    tar -xzf "$archive_file" -C "$temp_dir"

    local binary_path="$temp_dir/$BINARY_NAME"

    if [ ! -f "$binary_path" ]; then
        log_error "Binary not found in archive"
        exit 1
    fi

    log_info "Installing to $install_dir..."
    mkdir -p "$install_dir"
    cp "$binary_path" "$install_dir/"
    chmod +x "$install_dir/$BINARY_NAME"

    log_info "Creating cu symlink for backward compatibility..."
    ln -sf "$BINARY_NAME" "$install_dir/cu"

    # Clean up
    rm -rf "$temp_dir"

    log_success "$BINARY_NAME installed successfully!"
}

# Main installation process
main() {
    # Handle command line arguments
    case "${1:-}" in
        -h|--help)
            echo "container-use installer"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -h, --help    Show this help message"
            echo ""
            echo "This script will:"
            echo "  1. Check for Docker installation"
            echo "  2. Detect your OS and architecture"
            echo "  3. Download the latest container-use binary"
            echo "  4. Install 'container-use' binary and create 'cu' shortcut"
            echo "  5. Provide instructions to set up shell completions for both commands"
            exit 0
            ;;
    esac

    log_info "Starting container-use installation..."

    check_dependencies

    local os=$(detect_os)
    local arch=$(detect_arch)
    log_info "Detected platform: $os/$arch"

    local version=$(get_latest_version)
    if [ -z "$version" ]; then
        log_error "Failed to get latest release version"
        exit 1
    fi
    log_info "Latest version: $version"

    INSTALL_DIR=$(find_install_dir)
    log_info "Installation directory: $INSTALL_DIR"

    download_and_install "$os" "$arch" "$version" "$INSTALL_DIR"

    # Check if install directory is in PATH
    if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
        log_warning "Installation directory $INSTALL_DIR is not in your PATH"
        log_info "Add this to your shell profile (.bashrc, .zshrc, etc.):"
        echo "    export PATH=\"$INSTALL_DIR:\$PATH\""
        log_info "Then restart your terminal or run: source ~/.bashrc (or your shell's config file)"
    fi

    # Verify installation
    if [ -x "$INSTALL_DIR/$BINARY_NAME" ]; then
        log_success "Installation complete!"

        # Show shell completion instructions
        show_completion_instructions "$BINARY_NAME"

        # Verify installation
        if command -v "$BINARY_NAME" >/dev/null 2>&1 && command -v "cu" >/dev/null 2>&1; then
            log_success "container-use is ready to use!"
        else
            log_warning "You may need to restart your terminal or update your PATH"
        fi

        log_info "Run 'container-use --help' or 'cu --help' to get started"
    else
        log_error "Installation verification failed"
        exit 1
    fi
}

main "$@"
