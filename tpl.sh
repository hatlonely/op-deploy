#!/usr/bin/env bash

function Trac() {
    echo "[TRAC] [$(date +"%Y-%m-%d %H:%M:%S")] $1"
}

function Info() {
    echo "\033[1;32m[INFO] [$(date +"%Y-%m-%d %H:%M:%S")] $1\033[0m"
}

function Warn() {
    echo "\033[1;31m[WARN] [$(date +"%Y-%m-%d %H:%M:%S")] $1\033[0m"
    return 1
}

function List() {
    find gotpl -type d -depth 1 | awk '{print(substr($0, 7, length($0)))}'
}

function RenderGo() {
    environment=$1
    cfg=$2
    mkdir -p "tmp/${environment}"
    gomplate -f "gotpl/${environment}/environment.sh.tpl" -c .="${cfg}" > "tmp/${environment}/environment.sh" &&
    Info "[gomplate -f \"gotpl/${environment}/environment.sh.tpl\" -c .=\"${cfg}\" > \"tmp/${environment}/environment.sh\"] success" ||
    Warn "[gomplate -f \"gotpl/${environment}/environment.sh.tpl\" -c .=\"${cfg}\" > \"tmp/${environment}/environment.sh\"] failed"
}

function RenderSh() {
    environment=$1
    # shellcheck source=tmp/environment.sh
    source "tmp/${environment}/environment.sh"
    find shtpl -type f -depth 1 -name "*.tpl" | while read -r tpl; do
        out=${tpl%.*}
        out=${out#*/}
        out=tmp/${environment}/${out}
        eval "cat > \"${out}\" <<EOF
$(< "${tpl}")
EOF" && Info "render ${tpl} to ${out} success" || Warn "render ${tpl} to ${out} failed"
    done
}

function Render() {
    RenderGo "$1" "$2" && RenderSh "$1"
}

function Help() {
    echo "sh tpl.sh <action> [environment] [variable]"
    echo "example:"
    echo "  sh tpl.sh ls"
    echo "  sh tpl.sh render prod ~/.gomplate/prod.json"
}

function main() {
    case "$1" in
        "ls") List;;
        "render_go") RenderGo "$2" "$3";;
        "render_sh") RenderSh "$2";;
        "render") Render "$2" "$3";;
        *) Help;;
    esac
}

main "$@"
