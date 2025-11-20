#!/bin/bash

# 构建 sonic-client-web Docker 镜像的脚本
# 支持本地和远程 Docker 构建（使用 docker context）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认值
IMAGE_TAG="local"
EXPORT_FLAG=""
CONTEXT_NAME=""
REMOTE_DOCKER_HOST=""

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --tag|-t)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --export|-e)
            EXPORT_FLAG="export"
            shift
            ;;
        --context|-c)
            CONTEXT_NAME="$2"
            shift 2
            ;;
        --host)
            REMOTE_DOCKER_HOST="$2"
            shift 2
            ;;
        --help|-h)
            echo "构建 sonic-client-web Docker 镜像脚本"
            echo ""
            echo "使用方法:"
            echo "  $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --tag, -t <标签>          镜像标签，默认为 'local'"
            echo "  --export, -e              构建完成后自动导出镜像为 tar.gz 文件"
            echo "  --context, -c <名称>      Docker context 名称，用于远程构建"
            echo "  --host <地址>             远程 Docker daemon 地址（用于自动创建 context）"
            echo "  --help, -h                显示此帮助信息"
            echo ""
            echo "示例:"
            echo "  $0                                    # 本地构建，标签为 local"
            echo "  $0 --tag v2.4.1                      # 本地构建，标签为 v2.4.1"
            echo "  $0 --tag v2.4.1 --export            # 本地构建并导出"
            echo "  $0 --context remote                  # 使用 'remote' context 构建"
            echo "  $0 --tag v2.4.1 --export --context remote --host tcp://192.168.1.100:2376"
            echo "                                       # 自动创建并使用 'remote' context，构建并导出"
            echo ""
            echo "环境变量（用于 TLS 配置）:"
            echo "  DOCKER_TLS_CERT    - TLS 证书路径 (cert.pem)"
            echo "  DOCKER_TLS_KEY     - TLS 密钥路径 (key.pem)"
            echo "  DOCKER_TLS_CA      - TLS CA 证书路径 (ca.pem)"
            echo ""
            exit 0
            ;;
        *)
            echo -e "${RED}错误: 未知参数 '$1'${NC}"
            echo "使用 --help 查看帮助信息"
            exit 1
            ;;
    esac
done

# 保存当前 context
CURRENT_CONTEXT=$(docker context ls --format "{{if .Current}}{{.Name}}{{end}}" | head -1)
if [ -z "$CURRENT_CONTEXT" ]; then
    CURRENT_CONTEXT="default"
fi

# 如果指定了 context 名称，切换到该 context
if [ -n "$CONTEXT_NAME" ]; then
    echo -e "${BLUE}检查 Docker context: ${CONTEXT_NAME}${NC}"
    
    # 检查 context 是否存在
    if ! docker context ls --format "{{.Name}}" | grep -q "^${CONTEXT_NAME}$"; then
        echo -e "${YELLOW}Context '${CONTEXT_NAME}' 不存在，准备创建...${NC}"
        
        # 如果没有提供远程地址，提示用户输入
        if [ -z "$REMOTE_DOCKER_HOST" ]; then
            echo -e "${YELLOW}请输入远程 Docker daemon 地址:${NC}"
            echo -e "  ${YELLOW}示例: tcp://192.168.1.100:2376${NC}"
            read -p "远程 Docker 地址: " REMOTE_DOCKER_HOST
            
            if [ -z "$REMOTE_DOCKER_HOST" ]; then
                echo -e "${RED}错误: 未提供远程 Docker 地址，取消创建 context${NC}"
                exit 1
            fi
        fi
        
        # 创建 context（无 TLS）
        echo -e "${YELLOW}正在创建 context '${CONTEXT_NAME}'...${NC}"
        
        # 检查是否有 TLS 证书配置
        if [ -n "$DOCKER_TLS_CERT" ] && [ -n "$DOCKER_TLS_KEY" ] && \
           [ -f "$DOCKER_TLS_CERT" ] && [ -f "$DOCKER_TLS_KEY" ]; then
            echo -e "${BLUE}检测到 TLS 配置，将创建带 TLS 的 context${NC}"
            
            # 创建带 TLS 的 context
            if [ -n "$DOCKER_TLS_CA" ] && [ -f "$DOCKER_TLS_CA" ]; then
                docker context create "$CONTEXT_NAME" \
                    --docker "host=${REMOTE_DOCKER_HOST}" \
                    --docker "tls=true" \
                    --docker "tlscert=${DOCKER_TLS_CERT}" \
                    --docker "tlskey=${DOCKER_TLS_KEY}" \
                    --docker "tlscacert=${DOCKER_TLS_CA}"
            else
                docker context create "$CONTEXT_NAME" \
                    --docker "host=${REMOTE_DOCKER_HOST}" \
                    --docker "tls=true" \
                    --docker "tlscert=${DOCKER_TLS_CERT}" \
                    --docker "tlskey=${DOCKER_TLS_KEY}"
            fi
        else
            # 创建无 TLS 的 context
            docker context create "$CONTEXT_NAME" \
                --docker "host=${REMOTE_DOCKER_HOST}"
        fi
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}错误: 创建 context 失败${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}✓ Context '${CONTEXT_NAME}' 创建成功${NC}"
    fi
    
    echo -e "${BLUE}切换到 Docker context: ${CONTEXT_NAME}${NC}"
    
    # 切换到指定的 context
    docker context use "$CONTEXT_NAME" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: 无法切换到 context '${CONTEXT_NAME}'${NC}"
        exit 1
    fi
    
    # 设置退出时恢复原 context
    trap "docker context use '$CURRENT_CONTEXT' > /dev/null 2>&1" EXIT
fi

echo -e "${GREEN}开始构建 sonic-client-web Docker 镜像...${NC}"

# 检查 Docker 是否可用
if ! docker info > /dev/null 2>&1; then
    if [ -n "$CONTEXT_NAME" ]; then
        echo -e "${RED}错误: 无法连接到远程 Docker (context: ${CONTEXT_NAME})${NC}"
        echo -e "${YELLOW}请检查:${NC}"
        echo -e "  1. 远程 Docker daemon 是否运行"
        echo -e "  2. 网络连接是否正常"
        echo -e "  3. 防火墙是否允许连接"
        echo -e "  4. Context 配置是否正确"
    else
        echo -e "${RED}错误: Docker daemon 未运行，请先启动 Docker Desktop${NC}"
    fi
    # 恢复原 context
    docker context use "$CURRENT_CONTEXT" > /dev/null 2>&1
    exit 1
fi

# 显示当前使用的 Docker 信息
CURRENT_CONTEXT_NAME=$(docker context ls --format "{{if .Current}}{{.Name}}{{end}}" | head -1)
if [ -z "$CURRENT_CONTEXT_NAME" ]; then
    CURRENT_CONTEXT_NAME="default"
fi
echo -e "${BLUE}当前 Docker context: ${CURRENT_CONTEXT_NAME}${NC}"
DOCKER_INFO=$(docker info 2>/dev/null | grep -E "Server Version|Operating System" | head -2 || echo "")
if [ -n "$DOCKER_INFO" ]; then
    echo -e "${BLUE}Docker 信息:${NC}"
    echo "$DOCKER_INFO" | sed 's/^/  /'
fi

# 检查 dist/ 目录是否存在
if [ ! -d "dist" ]; then
    echo -e "${YELLOW}dist/ 目录不存在，正在构建前端项目...${NC}"
    npm run build
    if [ ! -d "dist" ]; then
        echo -e "${RED}错误: 构建失败，dist/ 目录未生成${NC}"
        exit 1
    fi
    echo -e "${GREEN}前端构建完成${NC}"
fi

# 检查基础镜像是否存在
BASE_IMAGE="sonicorg/sonic-client-web-base:v1.0.0"
if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${BASE_IMAGE}$"; then
    echo -e "${YELLOW}基础镜像 ${BASE_IMAGE} 不存在，正在拉取...${NC}"
    if ! docker pull "$BASE_IMAGE"; then
        echo -e "${RED}错误: 无法拉取基础镜像 ${BASE_IMAGE}${NC}"
        echo -e "${YELLOW}提示: 请检查网络连接或 Docker Hub 访问权限${NC}"
        exit 1
    fi
    echo -e "${GREEN}基础镜像拉取完成${NC}"
fi

# 构建镜像
IMAGE_NAME="sonic-client-web"

echo -e "${GREEN}正在构建 Docker 镜像: ${IMAGE_NAME}:${IMAGE_TAG}${NC}"
if [ -n "$CONTEXT_NAME" ]; then
    echo -e "${YELLOW}注意: 正在远程构建 (context: ${CONTEXT_NAME})，构建上下文将上传到远程服务器${NC}"
fi
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Docker 镜像构建成功: ${IMAGE_NAME}:${IMAGE_TAG}${NC}"
    echo ""
    echo -e "${GREEN}镜像信息:${NC}"
    docker images "${IMAGE_NAME}:${IMAGE_TAG}"
    echo ""
    echo -e "${GREEN}可以使用以下命令:${NC}"
    echo -e "  ${YELLOW}# 运行容器:${NC}"
    echo -e "  ${YELLOW}docker run -d -p 80:80 --name sonic-client-web ${IMAGE_NAME}:${IMAGE_TAG}${NC}"
    echo ""
    echo -e "  ${YELLOW}# 导出镜像为文件:${NC}"
    echo -e "  ${YELLOW}docker save -o ${IMAGE_NAME}-${IMAGE_TAG}.tar ${IMAGE_NAME}:${IMAGE_TAG}${NC}"
    echo -e "  ${YELLOW}# 或压缩导出:${NC}"
    echo -e "  ${YELLOW}docker save ${IMAGE_NAME}:${IMAGE_TAG} | gzip > ${IMAGE_NAME}-${IMAGE_TAG}.tar.gz${NC}"
    
    # 如果提供了第二个参数为 "export"，自动导出镜像
    if [ "$EXPORT_FLAG" = "export" ]; then
        EXPORT_FILE="${IMAGE_NAME}-${IMAGE_TAG}.tar.gz"
        echo ""
        echo -e "${YELLOW}正在导出镜像为 ${EXPORT_FILE}...${NC}"
        docker save "${IMAGE_NAME}:${IMAGE_TAG}" | gzip > "$EXPORT_FILE"
        if [ $? -eq 0 ]; then
            FILE_SIZE=$(du -h "$EXPORT_FILE" | cut -f1)
            echo -e "${GREEN}✓ 镜像已导出: ${EXPORT_FILE} (${FILE_SIZE})${NC}"
        else
            echo -e "${RED}✗ 镜像导出失败${NC}"
        fi
    fi
else
    echo -e "${RED}✗ Docker 镜像构建失败${NC}"
    exit 1
fi

