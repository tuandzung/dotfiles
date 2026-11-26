status is-interactive; or exit

abbr -a cz chezmoi
abbr -a cza 'chezmoi apply'
abbr -a czA 'chezmoi add'
abbr -a czAe 'chezmoi add --encrypt'
abbr -a cze 'chezmoi edit'
# Scripts stay out of the diff: rendering them can read secrets, which the
# diff would print in clear.
abbr -a czd 'chezmoi diff --recursive --exclude scripts'
abbr -a czu 'chezmoi update'
abbr -a czs 'chezmoi status'

abbr -a czDd 'chezmoi dycrypt decrypt'
abbr -a czDe 'chezmoi dycrypt encrypt'

abbr -a rcza 'rootmoi apply'
abbr -a rczA 'rootmoi add'
abbr -a rczAe 'rootmoi add --encrypt'
abbr -a rcze 'rootmoi edit'
# Scripts stay out of the system diff: rendering them may read secrets and the
# diff would print those in clear.
abbr -a rczd 'rootmoi diff --recursive --exclude scripts'
abbr -a rczu 'rootmoi update'
abbr -a rczs 'rootmoi status'

alias fcz __caran_fzf_chezmoi_edit

# The fzf picker takes no argument
complete -c fcz -f
