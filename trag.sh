#!/bin/bash

# Define list of packages to install
aurhelper="paru"
vimrepo="https://github.com/tragdate/soyvim.git"

error() {
	# Log to stderr and exit with failure.
	printf "%s\n" "$1" >&2
	exit 1
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            arch) DISTRO="arch" ;;
            debian) DISTRO="debian" ;;
            ubuntu) DISTRO="ubuntu" ;;
            alpine) DISTRO="alpine" ;;
            *) DISTRO="unknown" ;;
        esac
    else
        DISTRO="unknown"
    fi
}

install_whiptail() {
    if ! command -v whiptail >/dev/null 2>&1; then
        echo "'Whiptail' is not installed. Attempting to install it..."
        if [ "$DISTRO" == "arch" ]; then
            sudo pacman -Sy --noconfirm libnewt || echo "Failed to install 'whiptail'. Please install it manually."
        elif [ "$DISTRO" == "debian" ] || [ "$DISTRO" == "ubuntu" ]; then
            sudo apt-get update && sudo apt-get install -y whiptail || echo "Failed to install 'whiptail'. Please install it manually."
        elif [ "$DISTRO" == "alpine" ]; then
            sudo apk add newt || echo "Failed to install 'whiptail'. Please install it manually."
        else
            echo "Unsupported distribution: $DISTRO. Script will now exit."
        fi
    fi
}


welcomemsg() {
	whiptail --title "Welcome!" \
		--msgbox "Stai JOS!\\n\\nSe ocupa frateletau TragDate\\n\\n-In Bani Gata" 10 60

	whiptail --title "Bro!" --yes-button "Merge" \
		--no-button "Return..." \
		--yesno "Be sure the computer you are using has current pacman updates and refreshed Arch keyrings.\\n\\nIf it does not, the installation of some programs might fail." 8 70
}

getuserandpass() {
	# Prompts user for new username and password.
	name=$(whiptail --inputbox "Numele contului pe care se instaleaza TRAG." 10 60 3>&1 1>&2 2>&3 3>&1) || exit 1
	while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		name=$(whiptail --nocancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
	pass1=$(whiptail --nocancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
	pass2=$(whiptail --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
		pass1=$(whiptail --nocancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
		pass2=$(whiptail --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
}

# Function to create a new user with standardized settings
create_user() {
    local USERNAME=$name
    local PASSWORD=$pass1

    # Determine the primary sudo/wheel group
    if [ "$DISTRO" == "arch" ]; then
        SUDO_GROUP="wheel"
    elif [ "$DISTRO" == "debian" ] || [ "$DISTRO" == "ubuntu" ]; then
        SUDO_GROUP="sudo"
    elif [ "$DISTRO" == "alpine" ]; then
        SUDO_GROUP="wheel"  # Alpine uses 'wheel' for sudo access
    else
        echo "Unsupported distribution: $DISTRO"
        exit 1
    fi

    # Create user and set up group/shell
    if [ "$DISTRO" == "arch" ]; then
        useradd -m -g "$SUDO_GROUP" -s /bin/zsh "$USERNAME" >/dev/null 2>&1 ||
        usermod -aG "$SUDO_GROUP" "$USERNAME"
    elif [ "$DISTRO" == "debian" ] || [ "$DISTRO" == "ubuntu" ]; then
        adduser --disabled-password --gecos "" "$USERNAME"
        usermod -aG "$SUDO_GROUP" "$USERNAME"
        usermod -s /bin/zsh "$USERNAME"
    elif [ "$DISTRO" == "alpine" ]; then
        adduser -D -s /bin/zsh "$USERNAME"
        addgroup "$USERNAME" "$SUDO_GROUP"  # Alpine fix: use addgroup instead of usermod
    fi

    # Ensure home directory exists and correct ownership
    mkdir -p /home/"$USERNAME"
    chown "$USERNAME:$SUDO_GROUP" /home/"$USERNAME"

    # Set up a local repository directory for the user
    export repodir="/home/$USERNAME/.local/src"
    mkdir -p "$repodir"
    chown -R "$USERNAME:$SUDO_GROUP" "$(dirname "$repodir")"

    # FOR VM TESTING
    # sudo usermod -aG vboxsf $USERNAME

    # Set password
    echo "$USERNAME:$PASSWORD" | chpasswd
}


usercheck() {
	! { id -u "$name" >/dev/null 2>&1; } ||
		whiptail --title "WARNING" --yes-button "CONTINUE" \
			--no-button "No wait..." \
			--yesno "The user \`$name\` already exists on this system. TRAG can install for a user already existing, but it will OVERWRITE any conflicting settings/dotfiles on the user account.\\n\\nTRAG will NOT overwrite your user files, documents, videos, etc., so don't worry about that, but only click <CONTINUE> if you don't mind your settings being overwritten.\\n\\nNote also that TRAG will change $name's password to the one you just gave." 14 70
}

getinstalltype() {
    if [ "$DISTRO" == "arch" ]; then 
        # Arch users must choose between Server or User Install
        install_type=$(whiptail --title "Installation Type" --menu "Choose installation type" 15 60 2 \
            "0" "Server Install" \
            "1" "User Install" 3>&1 1>&2 2>&3)
    else
        # Default to Server Install for all other distros
        install_type=0
    fi
}

preinstallmsg() {
	whiptail --title "Let's get this party started!" --yes-button "Let's go!" \
		--no-button "No, nevermind!" \
		--yesno "The rest of the installation will now be totally automated, so you can sit back and relax.\\n\\nIt will take some time, but when done, you can relax even more with your complete system.\\n\\nNow just press <Let's go!> and the system will begin installation!" 13 60 || {
		clear
		exit 1
	}
}

refresh_keys() {
    case "$DISTRO" in
        arch)
            # whiptail --infobox "Refreshing Arch Keyring..." 7 50
            # sudo rm -rf /etc/pacman.d/gnupg
            # gpgconf --kill gpg-agent
            # gpgconf --launch gpg-agent
            # mkdir -p /etc/pacman.d/gnupg
            # chown -R root:root /etc/pacman.d/gnupg
            # chmod 700 /etc/pacman.d/gnupg
            pacman-key --init
            pacman-key --populate archlinux
            pacman --noconfirm -Sy archlinux-keyring >/dev/null 2>&1
            pacman --noconfirm -Su >/dev/null 2>&1
            ;;
        debian|ubuntu)
            # whiptail --infobox "Refreshing Debian/Ubuntu Keyring..." 7 50
            apt-get update -y >/dev/null 2>&1
            apt-get install --reinstall -y debian-archive-keyring >/dev/null 2>&1
            ;;

        alpine)
            # whiptail --infobox "Refreshing Alpine Keyring..." 7 50
            apk update >/dev/null 2>&1
            apk fix alpine-keys >/dev/null 2>&1
            ;;

        *)
            # whiptail --msgbox "Unsupported distribution: $DISTRO" 7 50
            exit 1
            ;;
    esac
}

install_package() {
    local PACKAGE=$1  # Take the package name as an argument
    local OPTIONS=$2
    if [ -z "$PACKAGE" ]; then
        echo "Error: No package specified for installation."
        return 1
    fi

    case "$DISTRO" in
        arch)
            pacman -Syu --noconfirm "$PACKAGE"
            ;;
        debian|ubuntu)
            apt install -y "$PACKAGE" "$2"
            ;;
        alpine)
            apk add "$PACKAGE" "$2"
            ;;
        *)
            echo "Unsupported distribution: $DISTRO"
            return 1
            ;;
    esac
}

install_mandatory_dependencies() {
    if [ "$DISTRO" == "debian" ] || [ "$DISTRO" == "ubuntu" ]; then
        apt update
    elif [ "$DISTRO" == "alpine" ]; then
        apk update
    fi

    case "$DISTRO" in
        arch)
            install_package "base-devel"
            ;;
        debian|ubuntu)
            apt install -y "build-essential"
            ;;
        alpine)
            apk add "build-base"
            ;;
        *)
            echo "Unsupported distribution: $DISTRO"
            return 1
            ;;
    esac

    for x in curl ca-certificates git ntp zsh; do
	    whiptail --title "TRAG Installation" \
		    --infobox "Installing \`$x\` which is required to install and configure other programs." 8 70
	    install_package "$x"
    done
}

sync_sys_time() {
    whiptail --title "TRAG Installation" \
	    --infobox "Synchronizing system time to ensure successful and secure installation of software..." 8 70

    if [ "$DISTRO" == "arch" ]; then
        ntpd -q -g >/dev/null 2>&1
    elif [ "$DISTRO" == "debian" ] || [ "$DISTRO" == "ubuntu" ]; then
        echo "[Debian] Stopping time services..."
        
        systemctl stop systemd-timesyncd 2>/dev/null || true
        systemctl stop chronyd 2>/dev/null || true
        systemctl stop ntp 2>/dev/null || true

        ntpd -q -g

        systemctl start systemd-timesyncd 2>/dev/null || true
        systemctl start chronyd 2>/dev/null || true
        systemctl start ntp 2>/dev/null || true

    elif [ "$DISTRO" == "alpine" ]; then
        echo "Alpine in development"
    fi 
}

configure_sudo() {
    # Save configuration if an update to sudo occured
    # Check for .pacnew (Arch-based), .dpkg-new (Debian/Ubuntu), or .apk-new (Alpine)
    if [ -f /etc/sudoers.pacnew ]; then
        cp /etc/sudoers.pacnew /etc/sudoers
    elif [ -f /etc/sudoers.dpkg-new ]; then
        cp /etc/sudoers.dpkg-new /etc/sudoers
    elif [ -f /etc/sudoers.apk-new ]; then
        cp /etc/sudoers.apk-new /etc/sudoers
    fi

    # Allow user to run sudo without password. Since AUR programs must be installed
    # in a fakeroot environment, this is required for all builds with AUR.
    if [ "$DISTRO" == "arch" ]; then
        
        # Ensure %wheel is enabled in sudoers
        echo "%wheel ALL=(ALL:ALL) ALL" | EDITOR='tee -a' visudo

        trap 'rm -f /etc/sudoers.d/larbs-temp' HUP INT QUIT TERM PWR EXIT
        echo "%wheel ALL=(ALL) NOPASSWD: ALL
        Defaults:%wheel,root runcwd=*" >/etc/sudoers.d/larbs-temp

        # Make pacman colorful, concurrent downloads and Pacman eye-candy.
        # grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
        # sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//" /etc/pacman.conf
    fi
}

use_all_cores() {
    # Use all cores for compilation
    if [ -f /etc/makepkg.conf ]; then  # Arch-based systems
        sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf
    elif [ -f /etc/default/make ]; then  # Debian-based systems
        sed -i "s/^-j2/-j$(nproc)/" /etc/default/make
    elif [ -f /etc/mk.conf ]; then  # Alpine Linux (sometimes used for compilation flags)
        sed -i "s/-j2/-j$(nproc)/" /etc/mk.conf
    else
        echo "No compatible configuration file found for setting MAKEFLAGS."
    fi
}

rustup() {
    # Rustup must be run from the created user
    sudo -u "$name" -H bash -c \
    "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs |
    sh -s -- -y --default-host x86_64-unknown-linux-gnu"

    . "/home/$name/.cargo/env"

    if [ "$DISTRO" == "arch" ]; then 
        # using git and not `cargo install paru` as it has a currently broken install script, 
        # it is trying to fetch dependency versions incompatible with each other. should be modified when this is fixed
        # also, all cargo installs must be done by the user
        sudo -u "$name" -H bash -c "
            if [ -f \"\$HOME/.cargo/env\" ]; then
                . \"\$HOME/.cargo/env\"
            fi
            cargo install --git https://github.com/Morganamilo/paru.git
        "

    fi
}

gitmakeinstall() {
	local progname="${1##*/}"
	local progname="${progname%.git}"
	dir="$repodir/$progname"
    echo "Installing program $progname"
	whiptail --title "TRAG Installation" \
		--infobox "Installing \`$progname\` ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2" 8 70
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "$1" "$dir" ||
		{
			cd "$dir" || return 1
			sudo -u "$name" git pull --force origin master
		}
	cd "$dir" || exit 1
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return 1
}

maininstall() {
	# Installs all needed programs from main repo.
	whiptail --title "TRAG Installation" --infobox "Installing \`$1\` ($n of $total). $1 $2" 9 70
	install_package "$1" $2
}

cargoinstall() {
	whiptail --title "TRAG Installation" \
		--infobox "Installing \`$1\` ($n of $total) from Cargo. $1 $2" 9 70

	# cargo install "$1" $2 does not work here as we must run cargo installs from the user, not as root.
    sudo -u "$name" -H bash -c "
        if [ -f \"\$HOME/.cargo/env\" ]; then
            . \"\$HOME/.cargo/env\"
        fi
        cargo install \"$1\" $2
    "


}

pipinstall() {
	whiptail --title "TRAG Installation" \
		--infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 9 70
	[ -x "$(command -v "pip")" ] || install_package python-pip 
	yes | pip install "$1" $2
}

aurinstall() {
	whiptail --title "TRAG Installation" \
		--infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 9 70
	echo "$aurinstalled" | grep -q "^$1$" && return 1
	sudo -u "$name" $aurhelper -S --noconfirm "$1" $2
}

primary_install_loop() {
    local csvfile="$1"  # The CSV file path
    local distro="$DISTRO"  # Make sure this is set from your detect_distro function!
    
    # Read the CSV, skipping the header line
    tail -n +2 "$csvfile" | while IFS=, read -r tag common_name arch_name debian_name alpine_name options description; do
        # Trim potential whitespace
        tag=$(echo "$tag" | xargs)
        common_name=$(echo "$common_name" | xargs)
        arch_name=$(echo "$arch_name" | xargs)
        debian_name=$(echo "$debian_name" | xargs)
        alpine_name=$(echo "$alpine_name" | xargs)
        description=$(echo "$description" | xargs)

        # Select the package name based on distro
        case "$distro" in
            arch)
                package_name="$arch_name"
                ;;
            debian|ubuntu)
                package_name="$debian_name"
                ;;
            alpine)
                package_name="$alpine_name"
                ;;
            *)
                echo "Unsupported distribution: $distro"
                continue
                ;;
        esac

        echo "installing $common_name $description"

        # Call the appropriate install function based on the tag
        case "$tag" in
            "C")
                cargoinstall "$package_name" "$options" >/dev/null 2>&1
                ;;
            "G")
                gitmakeinstall "$package_name" "$options" >/dev/null
                ;;
            "P")
                pipinstall "$package_name" "$options" >/dev/null 2>&1
                ;;
            "M")
                maininstall "$package_name" "$options" >/dev/null 2>&1
                ;;
            "A")
                aurinstall "$package_name" "$options" >/dev/null 2>&1
                ;;
            *)
                echo "Unknown tag '$tag' for $common_name. Skipping..."
                ;;
        esac
        # echo "installed $common_name"
    done
}

bun_install() {
    echo "installing bun"
    curl -fsSL https://bun.sh/install | bash
    export BUN_INSTALL="$HOME/.bun:$PATH"
    export PATH="$BUN_INSTALL/bin:$PATH"
}

nvim_install() {
    echo "installing nvim"

    su - "$name" -c 'PATH="/home/$name/.cargo/bin/bob:$PATH" bob use latest'

    sudo -u "$name" mkdir -p "/home/$name/.config/nvim"
    # local pwd_address="$(pwd)"
    # cd /home/$name/.config/nvim

	git clone --depth 1 "$vimrepo" "/home/$name/.config/nvim" >/dev/null 2>&1
    local pwd_address="$(pwd)"
	cd "/home/$name/.local/share/nvim/lazy/vim-hexokinase"
	make hexokinase >/dev/null 2>&1

    cd $pwd_address
}

zsh_config() {
    echo "putting dotfiles"

    chsh -s /usr/bin/zsh "$name" >/dev/null 2>&1
    echo "/usr/bin/zsh" >> /etc/shells
    echo "/bin/zsh" >> /etc/shells

    sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"
    sudo -u "$name" mkdir -p "/home/$name/.config/abook/"
    sudo -u "$name" mkdir -p "/home/$name/.config/mpd/playlists/"
    sudo -u "$name" mkdir -p "/home/$name/.config/zsh/"

    sudo -u "$name" cp "./.xprofile" "/home/$name/.config/zsh"
    sudo -u "$name" cp "./.zprofile" "/home/$name/.config/zsh"
    sudo -u "$name" cp "./.zshrc" "/home/$name/.config/zsh"
    sudo -u "$name" cp "./.zshenv" "/home/$name/"
}

### Base (server) install script execution
install_server() {
    # Detect the distribution
    detect_distro || error "User exited."

    # Refresh keyring
    refresh_keys || error "Automatic refresh of keyring failed. Consider doing so manually."

    # Install whiptail for the rest of the communication
    install_whiptail || error "User exited."

    # Print welcome message
    welcomemsg || error "User exited."

    # Get user and password from user
    getuserandpass || error "User exited."

    # Check if user exists
    usercheck || error "User exited."

    # Select if doing server or user installation
    getinstalltype || error "User exited."

    # Print preinstall message
    preinstallmsg || error "User exited."

    ### The rest of the script is automated, no user input required.

    # Install the packages
    install_mandatory_dependencies || error "Error installing mandatory dependencies"

    # Sync system time
    sync_sys_time || error "Error synchronizing the system time"

    # Create user and password 
    create_user || error "Error adding username and/or password."

    # Configure sudo
    configure_sudo || error "Error making sudo paswordless"

    # Enable all cores for compilation
    use_all_cores || error "Error trying to enable all cores for compilation"

    # Final zsh configuration
    zsh_config || error "Error configuring zsh"

    # Install rust
    # rustup || error "Error doing rustup"
    rustup

    # Install primary packages
    primary_install_loop "$(dirname "$0")/packages_server_common.csv" || error "Error installing common server packages"

    # Install bun
    bun_install || error "Error installing bun"

    # Install nvim & configure it
    nvim_install || error "Error installing nvim"


    echo "Server Installation completed for $DISTRO."
}

configure_videoserver() {
    sudo -u "$name" mkdir -p "/home/$name/.config/x11"

    sudo -u "$name" cp "./xinitrc" "/home/$name/.config/x11/"
    sudo -u "$name" cp "./xprofile" "/home/$name/.config/x11/"
}

user_install() {
    # Install GUI and other user packages
    primary_install_loop "$(dirname "$0")/packages_client_arch.csv" || error "Error installing user packages"

    configure_videoserver
}

restore_sudo() {
    if [ "$DISTRO" == "arch" ]; then
        # Remove the temporary sudoers file that allowed passwordless sudo
        rm -f /etc/sudoers.d/larbs-temp
        # Clear the trap that was set up to ensure the file was removed on exit
        trap - HUP INT QUIT TERM PWR EXIT
    fi
}

cleanup() {
    restore_sudo   
}

main() {
    install_server

    echo "$install_type"

    if [ "$install_type" == "1" ]; then 
        user_install
    fi

    cleanup
}

# Run the main function
main
