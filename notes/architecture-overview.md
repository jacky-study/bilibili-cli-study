---
article_id: OBA-xvag85mu
tags: [open-source, bilibili-cli, architecture-overview.md, python, cli]
type: learning
updated_at: 2026-03-26
---

# 研究发现: bilibili-cli 整体架构设计

> 一个结构清晰、分层合理的 Python CLI 工具，采用 Click + Rich + asyncio 技术栈，实现了命令模块化、认证策略化和输出格式化的设计模式。

## 一、基础概念

在开始之前，先了解几个核心概念：

| 概念 | 说明 |
|------|------|
| **Click** | Python 命令行工具框架，通过装饰器定义命令和参数 |
| **Rich** | 终端富文本渲染库，支持表格、颜色、进度条等 |
| **asyncio** | Python 异步编程框架，用于处理 I/O 密集型操作 |
| **bilibili-api-python** | Bilibili API 的 Python 封装库 |
| **Credential** | Bilibili 认证凭证对象，包含 SESSDATA、bili_jct 等 cookie |

## 二、项目结构

```
bili_cli/
├── __init__.py          # 版本信息（动态读取）
├── cli.py               # CLI 入口（Click group，注册所有命令）
├── client.py            # API 客户端（异步封装 bilibili-api）
├── auth.py              # 认证策略（保存/浏览器/二维码）
├── formatter.py         # 输出格式化（JSON/YAML/Rich）
├── payloads.py          # API 响应规范化
├── exceptions.py        # 自定义异常层次
└── commands/            # 命令模块目录
    ├── common.py        # 共享工具函数
    ├── account.py       # 登录/登出/状态/whoami
    ├── video.py         # 视频详情/字幕/评论
    ├── user_search.py   # 用户查询/搜索
    ├── collections.py   # 收藏/历史/动态
    ├── discovery.py     # 热门/排行榜
    ├── interactions.py  # 点赞/投币/三连
    └── audio.py         # 音频下载
```

## 三、关键代码位置

| 文件 | 行号 | 说明 |
|------|------|------|
| `cli.py` | 31-68 | CLI 入口和命令注册 |
| `client.py` | 53-88 | API 错误映射和统一调用 |
| `auth.py` | 44-100 | 认证策略（保存 → 浏览器 → 二维码） |
| `formatter.py` | 25-29 | 结构化输出装饰器 |
| `commands/common.py` | 37-60 | 异步/同步桥接和错误处理 |
| `commands/video.py` | 12-36 | 命令定义模式示例 |
| `commands/discovery.py` | 16-59 | 命令实现模式示例 |

## 四、架构设计原理

### 4.1 分层架构

```
┌─────────────────────────────────────────────┐
│  CLI Layer (cli.py + commands/*)            │  ← 用户交互层
│  • Click 命令定义                            │
│  • Rich 表格渲染                             │
│  • 参数解析和验证                            │
├─────────────────────────────────────────────┤
│  Business Layer                             │  ← 业务逻辑层
│  • formatter.py: 输出格式化                  │
│  • payloads.py: 数据规范化                   │
│  • common.py: 共享工具                       │
├─────────────────────────────────────────────┤
│  Service Layer (client.py + auth.py)        │  ← 服务层
│  • API 客户端封装                            │
│  • 认证策略管理                              │
│  • 错误转换和映射                            │
├─────────────────────────────────────────────┤
│  External Layer                             │  ← 外部依赖层
│  • bilibili-api-python                      │
│  • aiohttp                                  │
│  • browser-cookie3                          │
└─────────────────────────────────────────────┘
```

### 4.2 CLI 入口设计

**核心代码** (`cli.py`):

```python
# 1. 定义 Click group
@click.group()
@click.version_option(version=__version__, prog_name="bili")
@click.option("-v", "--verbose", is_flag=True, help="Enable debug logging.")
def cli(verbose: bool):
    """bili — Bilibili CLI tool 📺"""
    common.setup_logging(verbose)

# 2. 注册所有命令
cli.add_command(account.login)
cli.add_command(account.logout)
cli.add_command(video.video)
cli.add_command(user_search.search)
# ... 更多命令
```

**设计要点**：
- 使用 `@click.group()` 创建命令组，支持子命令
- 所有命令按功能模块分散在 `commands/` 目录
- 统一的 verbose 日志配置

### 4.3 命令模式

**标准命令模板** (`commands/video.py`):

```python
@click.command()
@click.argument("bv_or_url")
@click.option("--subtitle", "-s", is_flag=True, help="显示字幕内容。")
@click.option("--comments", "-c", is_flag=True, help="显示评论。")
@common.structured_output_options  # 添加 --json/--yaml
def video(bv_or_url: str, subtitle: bool, comments: bool, as_json: bool, as_yaml: bool):
    """查看视频详情。"""
    from .. import client

    # 1. 解析输出格式
    output_format = common.resolve_output_format(as_json=as_json, as_yaml=as_yaml)

    # 2. 获取认证（可选）
    cred = common.get_credential(mode="optional") if subtitle else None

    # 3. 调用 API（自动桥接 async → sync）
    info = common.run_or_exit(
        client.get_video_info(bvid, credential=None),
        "获取视频信息失败",
    )

    # 4. 输出结果（结构化或 Rich 表格）
    if common.emit_structured(data, output_format):
        return

    # 5. Rich 渲染
    table = Table(title="视频详情")
    # ... 渲染逻辑
```

**设计要点**：
1. **参数定义**：使用 Click 装饰器
2. **认证获取**：按需获取，支持多种认证模式
3. **异步桥接**：`common.run_or_exit()` 自动处理异步调用
4. **双模式输出**：结构化（JSON/YAML）或 Rich 表格

### 4.4 认证策略

**三级认证策略** (`auth.py`):

```python
def get_credential(mode: AuthMode = "read") -> Credential | None:
    """认证策略：保存 → 浏览器 → 二维码"""

    # 1. 尝试读取保存的凭证
    cred = _load_saved_credential()
    if cred:
        # 检查 TTL（7天），过期则尝试刷新
        if _is_credential_stale():
            fresh = _extract_browser_credential()
            if fresh and _validate_credential(fresh):
                save_credential(fresh)
                return fresh

        # 验证现有凭证
        if _validate_credential(cred):
            return cred

    # 2. 尝试从浏览器提取 cookie
    cred = _extract_browser_credential()
    if cred and _validate_credential(cred):
        save_credential(cred)
        return cred

    # 3. 可选模式：返回 None
    if mode == "optional":
        return None

    # 4. 需要认证但未获取到 → 提示登录
    print_login_required()
    return None
```

**认证模式** (`AuthMode`):
- `optional`：仅读取保存的凭证，不验证
- `read`：需要读取权限（SESSDATA）
- `write`：需要写入权限（bili_jct）

### 4.5 输出格式化

**双模式输出策略** (`formatter.py`):

```python
# 1. 结构化输出装饰器
def structured_output_options(command: Callable) -> Callable:
    """添加 --json/--yaml 选项"""
    command = click.option("--yaml", "as_yaml", is_flag=True)(command)
    command = click.option("--json", "as_json", is_flag=True)(command)
    return command

# 2. 解析输出格式
def resolve_output_format(*, as_json: bool, as_yaml: bool) -> OutputFormat:
    """优先级：参数 > 环境变量 > TTY 检测"""
    if as_yaml:
        return "yaml"
    if as_json:
        return "json"

    # 环境变量
    output_mode = os.getenv("OUTPUT", "auto").lower()
    if output_mode in ("yaml", "json"):
        return output_mode

    # 非终端 → 默认 YAML（对 AI Agent 友好）
    if not sys.stdout.isatty():
        return "yaml"

    return None  # Rich 模式

# 3. Schema Envelope（统一响应格式）
def success_payload(data: object) -> dict:
    return {
        "ok": True,
        "schema_version": "1",
        "data": data,
    }

def error_payload(code: str, message: str) -> dict:
    return {
        "ok": False,
        "schema_version": "1",
        "error": {"code": code, "message": message},
    }
```

**自动检测逻辑**：
- 交互式终端 → Rich 表格
- 管道/重定向 → YAML
- 环境变量 `OUTPUT=yaml/json` → 对应格式
- 参数 `--json/--yaml` → 强制指定格式

### 4.6 异步/同步桥接

**问题**：Click 命令是同步的，但 `bilibili-api-python` 是异步的

**解决方案** (`commands/common.py`):

```python
def run(coro):
    """桥接 async → sync"""
    import asyncio
    return asyncio.run(coro)

def run_or_exit(coro, action: str):
    """运行异步调用，自动转换错误为 CLI 友好消息"""
    try:
        return run(coro)
    except InvalidBvidError as e:
        exit_error(f"{action}: {e}", code="invalid_input")
    except AuthenticationError as e:
        exit_error(f"{action}: {e}", code="not_authenticated")
    except RateLimitError as e:
        exit_error(f"{action}: {e}", code="rate_limited")
    except NotFoundError as e:
        exit_error(f"{action}: {e}", code="not_found")
    except NetworkError as e:
        exit_error(f"{action}: {e}", code="network_error")
    except BiliError as e:
        exit_error(f"{action}: {e}", code="upstream_error")
    except Exception as e:
        exit_error(f"{action}: {e}", code="internal_error")
```

### 4.7 API 客户端设计

**薄封装模式** (`client.py`):

```python
# 1. 统一错误映射
def _map_api_error(action: str, exc: Exception) -> BiliError:
    """将第三方 API 异常转换为稳定本地异常"""
    if isinstance(exc, ResponseCodeException):
        code = getattr(exc, "code", None)
        if code in {-101, -111}:
            return AuthenticationError(f"{action}: {exc}")
        if code in {-404, 62002, 62004}:
            return NotFoundError(f"{action}: {exc}")
        if code in {-412, 412}:
            return RateLimitError(f"{action}: {exc}")
        return BiliError(f"{action}: [{code}] {exc}")

    if isinstance(exc, (NetworkException, aiohttp.ClientError)):
        return NetworkError(f"{action}: {exc}")

    return BiliError(f"{action}: {exc}")

# 2. 统一调用入口
async def _call_api(action: str, awaitable):
    """运行 API 调用并标准化错误"""
    try:
        return await awaitable
    except Exception as exc:
        raise _map_api_error(action, exc) from exc

# 3. API 函数示例
async def get_video_info(bvid: str, credential: Credential | None = None) -> dict:
    """获取视频信息"""
    v = video.Video(bvid=bvid, credential=credential)
    return await _call_api("获取视频信息", v.get_info())
```

**设计要点**：
- 所有 API 函数都是 `async`
- 接受可选的 `Credential` 参数
- 统一错误映射，不暴露第三方异常

## 五、设计亮点

### 1. **模块化命令组织**

按功能域划分命令模块，每个模块独立文件：
- `account.py` - 账户管理
- `video.py` - 视频相关
- `discovery.py` - 发现/热门
- `interactions.py` - 交互操作

### 2. **AI Agent 友好的输出设计**

- **Schema Envelope**：统一响应格式，便于解析
- **自动检测**：非 TTY 自动输出 YAML
- **推荐 YAML**：更适合 AI 处理（注释、可读性）

### 3. **认证策略的优雅降级**

```
保存凭证 → 浏览器 Cookie → 二维码登录 → optional 模式
```

避免强制登录，提升用户体验。

### 4. **错误处理的层次化**

```
第三方异常 → 本地异常 → 结构化错误输出
```

隔离外部依赖，提供稳定的错误 API。

### 5. **同步/异步的透明桥接**

命令层无需关心底层是同步还是异步，`run_or_exit()` 自动处理。

## 六、可复用模式

### 6.1 CLI 工具标准模板

```python
# cli.py
from click import group
from commands import account, video

@group()
def cli():
    """CLI 工具描述"""
    pass

cli.add_command(account.login)
cli.add_command(video.info)

if __name__ == "__main__":
    cli()
```

### 6.2 命令模块标准模板

```python
# commands/example.py
import click
from rich.table import Table
from . import common

@click.command()
@click.argument("id")
@click.option("--verbose", "-v", is_flag=True)
@common.structured_output_options
def example(id: str, verbose: bool, as_json: bool, as_yaml: bool):
    """命令描述"""
    from .. import client

    # 1. 解析输出格式
    output_format = common.resolve_output_format(as_json=as_json, as_yaml=as_yaml)

    # 2. 调用 API
    data = common.run_or_exit(
        client.get_data(id),
        "获取数据失败",
    )

    # 3. 结构化输出
    if common.emit_structured(data, output_format):
        return

    # 4. Rich 渲染
    table = Table(title="数据列表")
    # ... 渲染逻辑
    common.console.print(table)
```

### 6.3 异步客户端封装模板

```python
# client.py
from typing import Any
from bilibili_api.utils.network import Credential
from .exceptions import APIError, AuthError, NotFoundError

async def _call_api(action: str, awaitable):
    """统一 API 调用入口"""
    try:
        return await awaitable
    except Exception as exc:
        raise _map_error(action, exc) from exc

def _map_error(action: str, exc: Exception) -> APIError:
    """错误映射"""
    # 根据异常类型返回对应错误
    if "auth" in str(exc).lower():
        return AuthError(f"{action}: {exc}")
    if "not found" in str(exc).lower():
        return NotFoundError(f"{action}: {exc}")
    return APIError(f"{action}: {exc}")

# API 函数
async def get_data(id: str, credential: Credential | None = None) -> dict[str, Any]:
    """获取数据"""
    # 调用第三方 API
    return await _call_api("获取数据", third_party_api(id, credential))
```

### 6.4 认证策略模板

```python
# auth.py
from pathlib import Path
from typing import Literal

CONFIG_DIR = Path.home() / ".my-cli"
CREDENTIAL_FILE = CONFIG_DIR / "credential.json"
AuthMode = Literal["optional", "read", "write"]

def get_credential(mode: AuthMode = "read") -> Credential | None:
    """认证策略"""
    # 1. 尝试保存的凭证
    cred = _load_saved_credential()
    if cred and _validate_credential(cred):
        return cred

    # 2. 尝试浏览器
    cred = _extract_browser_credential()
    if cred and _validate_credential(cred):
        save_credential(cred)
        return cred

    # 3. 可选模式
    if mode == "optional":
        return None

    # 4. 提示登录
    print("请先登录: my-cli login")
    return None
```

## 七、参考资料

- [Click 官方文档](https://click.palletsprojects.com/)
- [Rich 官方文档](https://rich.readthedocs.io/)
- [bilibili-api-python](https://github.com/Nemo2011/bilibili-api)
- [Python asyncio 文档](https://docs.python.org/3/library/asyncio.html)
