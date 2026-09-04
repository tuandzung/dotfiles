function __caran_mise_env_eval --on-event fish_prompt --description 'Update mise environment when changing directories'
    if command -sq mise
        command mise hook-env -s fish | source

        if test "$mise_fish_mode" != disable_arrow
            function __caran_mise_cd_hook --on-variable PWD --description 'Update mise environment when changing directories'
                if test "$mise_fish_mode" = eval_after_arrow
                    set -g __caran_mise_env_again 0
                else
                    command mise hook-env -s fish | source
                end
            end
        end
    end
end

function __caran_mise_env_eval_2 --on-event fish_preexec --description 'Update mise environment when changing directories'
    if command -sq mise
        if set -q __caran_mise_env_again
            set -e __caran_mise_env_again
            command mise hook-env -s fish | source
            echo
        end

        functions --erase __caran_mise_cd_hook
    end
end

__caran_mise_env_eval 2>/dev/null; true

if functions -q fish_command_not_found; and not functions -q __caran_mise_fish_command_not_found
    functions -e __caran_mise_fish_command_not_found
    functions -c fish_command_not_found __caran_mise_fish_command_not_found
end

function fish_command_not_found
    if string match -qrv -- '^(?:mise$|mise-)' $argv[1] &&
            command -sq mise &&
            command mise hook-not-found -s fish -- $argv[1]
        command mise hook-env -s fish | source
    else if functions -q __caran_mise_fish_command_not_found
        __caran_mise_fish_command_not_found $argv
    else
        __fish_default_command_not_found_handler $argv
    end
end
