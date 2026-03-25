#!/bin/bash
# repo-study-status.sh - 查询当前目录研究状态

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认参数
JSON_OUTPUT=false
CHECK_REMOTE=false

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --check-remote)
            CHECK_REMOTE=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# 检查是否存在 .study-meta.json
if [ ! -f ".study-meta.json" ]; then
    if [ "$JSON_OUTPUT" = true ]; then
        echo '{"isRepoStudyProject": false, "error": "No .study-meta.json found"}'
    else
        echo -e "${RED}✗ 当前目录不是 repo-study 创建的项目${NC}"
    fi
    exit 0
fi

# 读取元数据
META=$(cat .study-meta.json)

# 判断是否 repo-study v2 管理
MANAGED_BY_SKILL=$(echo "$META" | jq -r '.managedBy.skill // ""')
CREATED_BY_SKILL=$(echo "$META" | jq -r '.managedBy.createdBySkill // false')

if [ "$MANAGED_BY_SKILL" = "repo-study" ] && [ "$CREATED_BY_SKILL" = "true" ]; then
    IS_REPO_STUDY=true
else
    IS_REPO_STUDY=false
fi

# 获取仓库名和 owner
REPO_NAME=$(echo "$META" | jq -r '.repo.name // .repoName // ""')
REPO_OWNER=$(echo "$META" | jq -r '.repo.owner // ""')
LOCAL_COMMIT=$(echo "$META" | jq -r '.repo.commitSha // .commitSha // ""')
GITHUB_URL=$(echo "$META" | jq -r '.repo.githubUrl // ""')

# 远程版本检查
REMOTE_CHECK_STATUS="unknown"
REMOTE_COMMIT=""
if [ "$CHECK_REMOTE" = true ] && [ -n "$REPO_OWNER" ] && [ -n "$REPO_NAME" ]; then
    REMOTE_COMMIT=$(gh api "repos/${REPO_OWNER}/${REPO_NAME}/commits/main" --jq '.sha' 2>/dev/null || echo "")
    if [ -n "$REMOTE_COMMIT" ]; then
        if [ "$LOCAL_COMMIT" = "$REMOTE_COMMIT" ]; then
            REMOTE_CHECK_STATUS="up_to_date"
        else
            REMOTE_CHECK_STATUS="outdated"
        fi
    fi
fi

# 提取 topics 信息
TOPICS=$(echo "$META" | jq -r '.topics // []')

if [ "$JSON_OUTPUT" = true ]; then
    # JSON 输出
    jq -n \
        --argjson isRepoStudyProject "$IS_REPO_STUDY" \
        --arg repoName "$REPO_NAME" \
        --arg localCommit "$LOCAL_COMMIT" \
        --arg remoteCheckStatus "$REMOTE_CHECK_STATUS" \
        --arg remoteCommit "$REMOTE_COMMIT" \
        --argjson topics "$TOPICS" \
        '{
            isRepoStudyProject: $isRepoStudyProject,
            repoName: $repoName,
            localCommit: $localCommit,
            remoteCheck: {
                status: $remoteCheckStatus,
                remoteCommit: $remoteCommit
            },
            topics: $topics
        }'
else
    # 可读输出
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  repo-study 状态查询${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if [ "$IS_REPO_STUDY" = true ]; then
        echo -e "${GREEN}✓ repo-study v2 管理的项目${NC}"
    else
        echo -e "${YELLOW}⚠ 非 repo-study 创建的项目${NC}"
    fi

    echo ""
    echo -e "${BLUE}项目信息:${NC}"
    echo "  仓库名称: $REPO_NAME"
    echo "  GitHub: $GITHUB_URL"
    echo "  本地版本: ${LOCAL_COMMIT:0:8}"

    if [ "$CHECK_REMOTE" = true ]; then
        if [ "$REMOTE_CHECK_STATUS" = "up_to_date" ]; then
            echo -e "  远程状态: ${GREEN}已是最新${NC}"
        elif [ "$REMOTE_CHECK_STATUS" = "outdated" ]; then
            echo -e "  远程状态: ${YELLOW}有更新${NC}"
            echo "  远程版本: ${REMOTE_COMMIT:0:8}"
        else
            echo -e "  远程状态: ${RED}无法检查${NC}"
        fi
    fi

    echo ""
    echo -e "${BLUE}研究课题:${NC}"

    # 解析 topics
    TOPIC_COUNT=$(echo "$TOPICS" | jq 'length')
    if [ "$TOPIC_COUNT" -eq 0 ]; then
        echo "  暂无研究课题"
    else
        echo "$TOPICS" | jq -r '.[] | "  • \(.name) - \(.state) (问题: \(.progress.questions), 笔记: \(.progress.notes))"' 2>/dev/null || \
        echo "$TOPICS" | jq -r '.[] | "  • \(.name)"'
    fi

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
fi
