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

function Build() {
    cd .. && make image && cd -
    docker login --username="${REGISTRY_USERNAME}" --password="${REGISTRY_PASSWORD}" "${REGISTRY_SERVER}"
    docker tag "${IMAGE_REPOSITORY}:${IMAGE_TAG}" "${REGISTRY_SERVER}/${IMAGE_REPOSITORY}:${IMAGE_TAG}"
    docker push "${REGISTRY_SERVER}/${IMAGE_REPOSITORY}:${IMAGE_TAG}"
}

function SQLTpl() {
    environment=$1
    kubectl run -n prod -it --rm sql --image=mysql:5.7.30 --restart=Never -- \
      mysql -uroot -h"${MYSQL_SERVER}" -p"${MYSQL_ROOT_PASSWORD}" -e "$(cat "tmp/${environment}/create_table.sql")"
}

function CreateNAMESPACEIfNotExists() {
    kubectl get namespaces "${NAMESPACE}" 2>/dev/null 1>&2 && return 0
    kubectl create namespace "${NAMESPACE}" &&
    Info "create namespace ${NAMESPACE} success" ||
    Warn "create namespace ${NAMESPACE} failed"
}

function CreatePULL_SECRETSIfNotExists() {
    kubectl get secret "${PULL_SECRETS}" -n "${NAMESPACE}" 2>/dev/null 1>&2 && return 0
    kubectl create secret docker-registry "${PULL_SECRETS}" \
        --docker-server="${REGISTRY_SERVER}" \
        --docker-username="${REGISTRY_USERNAME}" \
        --docker-password="${REGISTRY_PASSWORD}" \
        --namespace="prod" &&
    Info "[kubectl create secret docker-registry ${PULL_SECRETS}] success" ||
    Warn "[kubectl create secret docker-registry ${PULL_SECRETS}] failed"
}

function Render() {
    environment=$1
    variable=$2
    sh tpl.sh render "${environment}" "${variable}"
}

function Test() {
    kubectl run -n "${NAMESPACE}" -it --rm "${NAME}" --image="${REGISTRY_SERVER}/${IMAGE_REPOSITORY}:${IMAGE_TAG}" --restart=Never -- /bin/bash
}

function Install() {
    environment=$1
    helm install "${NAME}" -n "${NAMESPACE}" "./chart/${NAME}" -f "tmp/${environment}/chart.yaml"
}

function Upgrade() {
    environment=$1
    helm upgrade "${NAME}" -n "${NAMESPACE}" "./chart/${NAME}" -f "tmp/${environment}/chart.yaml"
}

function Diff() {
    environment=$1
    helm diff upgrade "${NAME}" -n "${NAMESPACE}" "./chart/${NAME}" -f "tmp/${environment}/chart.yaml"
}

function Delete() {
    helm delete "${NAME}" -n "${NAMESPACE}"
}

function Restart() {
    kubectl get pods -n "${NAMESPACE}" | grep "${NAME}" | awk '{print $1}' | xargs kubectl delete pods -n "${NAMESPACE}"
}

function Help() {
    echo "sh deploy.sh <environment> <action>"
    echo "example"
    echo "  sh deploy.sh prod build"
    echo "  sh deploy.sh prod sql"
    echo "  sh deploy.sh prod secret"
    echo "  sh deploy.sh prod render"
    echo "  sh deploy.sh prod install"
    echo "  sh deploy.sh prod upgrade"
    echo "  sh deploy.sh prod delete"
    echo "  sh deploy.sh prod diff"
    echo "  sh deploy.sh prod test"
    echo "  sh deploy.sh prod restart"
}

function main() {
    if [ -z "$2" ]; then
        Help
        return 0
    fi

    environment=$1
    action=$2

    # shellcheck source=tmp/$1/environment.sh
    source "tmp/$1/environment.sh"

    if [ "${K8S_CONTEXT}" != "$(kubectl config current-context)" ]; then
        Warn "context [${K8S_CONTEXT}] not match [$(kubectl config current-context)]"
        return 1
    fi

    case "${action}" in
        "build") Build;;
        "sql") SQLTpl "${environment}";;
        "secret") CreatePULL_SECRETSIfNotExists;;
        "render") Render "${environment}" "$3";;
        "install") Install "${environment}";;
        "upgrade") Upgrade "${environment}";;
        "diff") Diff "${environment}";;
        "delete") Delete;;
        "test") Test;;
        "restart") Restart;;
        *) Help;;
    esac
}

main "$@"
