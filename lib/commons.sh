#!/bin/sh

function indent() {
    local sed_command="s/^/       /"
    case "$(uname)" in
        Darwin)
            sed -l "${sed_command}"
            ;;
        *)
            sed -u "${sed_command}"
            ;;
    esac
}
