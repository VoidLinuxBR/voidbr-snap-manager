# avisa ao abrir o terminal se o sistema foi iniciado a partir de um snapshot
[[ $- == *i* ]] && command -v voidbr-snap-manager >/dev/null && voidbr-snap-manager check
