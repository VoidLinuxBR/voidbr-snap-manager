# avisa ao abrir o terminal se o sistema foi iniciado a partir de um snapshot
[[ $- == *i* ]] && command -v voidbr-snapper-manager >/dev/null && voidbr-snapper-manager check
