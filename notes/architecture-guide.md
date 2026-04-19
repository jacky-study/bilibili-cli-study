---
article_id: OBA-hbvb7t0s
tags: [open-source, bilibili-cli, architecture-guide.md, python, cli, ai]
type: tutorial
updated_at: 2026-03-26
---

# 实操指南：从零开始设计一个 Python CLI 工具

> 基于 bilibili-cli 的架构设计，手把手教你创建一个结构清晰、易扩展的命令行工具

## 一、准备工作

### 1.1 你将学到什么

学完这份指南，你将能够：

1. ✅ 使用 Click 创建模块化的 CLI 工具
2. ✅ 设计认证策略（保存/浏览器/二维码）
3. ✅ 实现双模式输出（Rich 表格 + 结构化数据）
4. ✅ 桥接异步 API 和同步 CLI
5. ✅ 设计层次化的错误处理

### 1.2 前置条件

在开始之前，请确保你已安装：

| 工具 | 版本要求 | 安装命令 |
|------|----------|----------|
| Python | 3.10+ | `brew install python` |
| pip | 最新 | `pip install --upgrade pip` |
| Git | 任意 | `brew install git` |

### 1.3 技术栈

我们将使用以下 Python 库：

| 库名 | 用途 | 安装命令 |
|------|------|----------|
| click | CLI 框架 | `pip install click` |
| rich | 终端渲染 | `pip install rich` |
| aiohttp | 异步 HTTP | `pip install aiohttp` |
| pyyaml | YAML 支持 | `pip install pyyaml` |

---

## 二、项目初始化

### 2.1 创建项目结构

```bash
# 1. 创建项目目录
mkdir my-cli-tool
cd my-cli-tool

# 2. 创建目录结构
mkdir -p my_cli/commands tests

# 3. 创建文件
touch my_cli/__init__.py
touch my_cli/cli.py
touch my_cli/client.py
touch my_cli/auth.py
touch my_cli/formatter.py
touch my_cli/exceptions.py
touch my_cli/commands/__init__.py
touch my_cli/commands/common.py
touch my_cli/commands/example.py
touch pyproject.toml
touch README.md
```

### 2.2 配置 pyproject.toml

创建 `pyproject.toml` 文件：

```toml
[project]
name = "my-cli-tool"
version = "0.1.0"
description = "A modular CLI tool"
requires-python = ">=3.10"
dependencies = [
    "click>=8.0",
    "rich>=13.0",
    "aiohttp>=3.0",
    "pyyaml>=6.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-asyncio>=0.23",
]

[project.scripts]
mycli = "my_cli.cli:cli"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["my_cli"]
```

**关键点解释**：
- `[project.scripts]` 定义了命令入口：运行 `mycli` 会调用 `my_cli.cli:cli` 函数
- `requires-python = ">=3.10"` 确保使用 Python 3.10+ 的特性

---

## 三、实现核心模块

### 3.1 定义异常层次

创建 `my_cli/exceptions.py`：

```python
"""自定义异常层次"""


class MyCLIError(Exception):
    """基础异常"""


class InvalidInputError(MyCLIError):
    """输入无效"""


class NetworkError(MyCLIError):
    """网络请求失败"""


class AuthenticationError(MyCLIError):
    """认证失败"""


class NotFoundError(MyCLIError):
    """资源未找到"""
```

**为什么需要自定义异常？**
- 隔离第三方库的异常，不暴露给用户
- 提供稳定的错误 API
- 便于错误处理和日志记录

### 3.2 实现输出格式化

创建 `my_cli/formatter.py`：

```python
"""输出格式化工具"""

import json
import os
import sys
from collections.abc import Callable
from typing import NoReturn

import click
import yaml
from rich.console import Console

console = Console(stderr=True)
OutputFormat = str | None
_SCHEMA_VERSION = "1"


def structured_output_options(command: Callable) -> Callable:
    """添加 --json/--yaml 选项到命令"""
    command = click.option("--yaml", "as_yaml", is_flag=True, help="输出 YAML")(command)
    command = click.option("--json", "as_json", is_flag=True, help="输出 JSON")(command)
    return command


def resolve_output_format(*, as_json: bool = False, as_yaml: bool = False) -> OutputFormat:
    """解析输出格式

    优先级：参数 > 环境变量 > TTY 检测
    """
    if as_json and as_yaml:
        exit_error("不能同时使用 --json 和 --yaml")

    if as_yaml:
        return "yaml"
    if as_json:
        return "json"

    # 检查环境变量
    output_mode = os.getenv("OUTPUT", "auto").strip().lower()
    if output_mode == "yaml":
        return "yaml"
    if output_mode == "json":
        return "json"

    # 非终端（管道/重定向）→ 默认 YAML
    if not sys.stdout.isatty():
        return "yaml"

    return None  # Rich 模式


def emit_structured(data: object, output_format: OutputFormat) -> bool:
    """输出结构化数据

    返回 True 表示已输出，False 表示需要 Rich 渲染
    """
    payload = _normalize_payload(data)

    if output_format == "json":
        click.echo(json.dumps(payload, ensure_ascii=False, indent=2))
        return True
    if output_format == "yaml":
        click.echo(yaml.safe_dump(payload, allow_unicode=True, sort_keys=False))
        return True

    return False


def success_payload(data: object) -> dict:
    """成功响应格式"""
    return {
        "ok": True,
        "schema_version": _SCHEMA_VERSION,
        "data": data,
    }


def error_payload(code: str, message: str, *, details: object | None = None) -> dict:
    """错误响应格式"""
    error: dict = {"code": code, "message": message}
    if details is not None:
        error["details"] = details
    return {
        "ok": False,
        "schema_version": _SCHEMA_VERSION,
        "error": error,
    }


def exit_error(message: str, *, code: str = "error", details: object | None = None) -> NoReturn:
    """输出错误并退出"""
    output_format = resolve_output_format()

    if output_format in ("json", "yaml"):
        payload = error_payload(code, message, details=details)
        if output_format == "json":
            click.echo(json.dumps(payload, ensure_ascii=False, indent=2))
        else:
            click.echo(yaml.safe_dump(payload, allow_unicode=True, sort_keys=False))
    else:
        console.print(f"[red]✗ {message}[/red]")

    sys.exit(1)


def _normalize_payload(data: object) -> object:
    """标准化响应格式"""
    if isinstance(data, dict) and data.get("schema_version") == _SCHEMA_VERSION and "ok" in data:
        return data
    return success_payload(data)
```

**设计要点**：
1. **装饰器模式**：`structured_output_options` 可以轻松添加到任何命令
2. **自动检测**：非终端自动输出 YAML，对 AI Agent 友好
3. **Schema Envelope**：统一响应格式，便于解析

### 3.3 实现命令工具函数

创建 `my_cli/commands/common.py`：

```python
"""命令模块共享工具"""

import asyncio
import logging

import click

from ..exceptions import (
    AuthenticationError,
    InvalidInputError,
    MyCLIError,
    NetworkError,
    NotFoundError,
)
from ..formatter import (
    OutputFormat,
    console,
    emit_structured,
    exit_error,
    resolve_output_format,
    structured_output_options,
)

# 重新导出 formatter 的所有函数，方便命令模块使用
__all__ = [
    "OutputFormat",
    "console",
    "emit_structured",
    "exit_error",
    "resolve_output_format",
    "structured_output_options",
    "setup_logging",
    "run",
    "run_or_exit",
]


def setup_logging(verbose: bool):
    """配置日志"""
    level = logging.DEBUG if verbose else logging.WARNING
    logging.basicConfig(level=level, format="%(name)s: %(message)s")


def run(coro):
    """桥接 async → sync"""
    return asyncio.run(coro)


def run_or_exit(coro, action: str):
    """运行异步调用，自动处理错误"""
    try:
        return run(coro)
    except InvalidInputError as e:
        exit_error(f"{action}: {e}", code="invalid_input")
    except AuthenticationError as e:
        exit_error(f"{action}: {e}", code="not_authenticated")
    except NotFoundError as e:
        exit_error(f"{action}: {e}", code="not_found")
    except NetworkError as e:
        exit_error(f"{action}: {e}", code="network_error")
    except MyCLIError as e:
        exit_error(f"{action}: {e}", code="upstream_error")
    except Exception as e:
        exit_error(f"{action}: {e}", code="internal_error")
```

**关键点**：
- `run()` 使用 `asyncio.run()` 桥接异步和同步
- `run_or_exit()` 统一处理所有错误，转换为友好的 CLI 输出

---

## 四、实现异步 API 客户端

### 4.1 创建 API 客户端

创建 `my_cli/client.py`：

```python
"""API 客户端 - 异步封装"""

import asyncio
import logging
from typing import Any

import aiohttp

from .exceptions import AuthenticationError, MyCLIError, NetworkError, NotFoundError

logger = logging.getLogger(__name__)

# 模拟的第三方 API
_THIRD_PARTY_API = "https://jsonplaceholder.typicode.com"


async def _call_api(action: str, awaitable):
    """统一 API 调用入口"""
    try:
        return await awaitable
    except Exception as exc:
        raise _map_error(action, exc) from exc


def _map_error(action: str, exc: Exception) -> MyCLIError:
    """映射错误到本地异常"""
    if isinstance(exc, MyCLIError):
        return exc

    # 网络错误
    if isinstance(exc, (aiohttp.ClientError, asyncio.TimeoutError)):
        return NetworkError(f"{action}: {exc}")

    # 可以根据实际情况添加更多映射
    return MyCLIError(f"{action}: {exc}")


async def get_example_data(item_id: str) -> dict[str, Any]:
    """获取示例数据

    这是一个示例 API 函数，你可以替换为实际的 API 调用
    """
    async with aiohttp.ClientSession() as session:
        url = f"{_THIRD_PARTY_API}/posts/{item_id}"
        async with session.get(url) as response:
            if response.status == 404:
                raise NotFoundError(f"未找到 ID 为 {item_id} 的数据")
            if response.status == 401:
                raise AuthenticationError("认证失败")
            if response.status != 200:
                raise MyCLIError(f"API 错误: {response.status}")

            return await _call_api("获取数据", response.json())


async def search_examples(query: str, limit: int = 10) -> list[dict[str, Any]]:
    """搜索示例数据"""
    async with aiohttp.ClientSession() as session:
        url = f"{_THIRD_PARTY_API}/posts"
        params = {"_limit": limit}

        async with session.get(url, params=params) as response:
            if response.status != 200:
                raise MyCLIError(f"搜索失败: {response.status}")

            data = await _call_api("搜索", response.json())

            # 简单的客户端过滤（实际应该由服务端处理）
            if query:
                data = [item for item in data if query.lower() in item.get("title", "").lower()]

            return data
```

**设计要点**：
1. **所有 API 函数都是 async**：与 Click 的同步特性隔离
2. **统一错误映射**：`_map_error()` 将第三方异常转换为本地异常
3. **薄封装**：API 函数只负责调用和错误转换，不处理业务逻辑

---

## 五、实现命令模块

### 5.1 创建示例命令

创建 `my_cli/commands/example.py`：

```python
"""示例命令"""

import click
from rich.table import Table

from . import common


@click.command()
@click.argument("id")
@click.option("--verbose", "-v", is_flag=True, help="显示详细信息")
@common.structured_output_options
def get(id: str, verbose: bool, as_json: bool, as_yaml: bool):
    """获取数据详情

    ID: 数据的唯一标识符
    """
    from .. import client

    # 1. 解析输出格式
    output_format = common.resolve_output_format(as_json=as_json, as_yaml=as_yaml)

    # 2. 调用 API（自动桥接 async → sync）
    data = common.run_or_exit(
        client.get_example_data(id),
        "获取数据失败",
    )

    # 3. 结构化输出
    if common.emit_structured(data, output_format):
        return

    # 4. Rich 渲染（交互式终端）
    table = Table(title=f"📄 数据详情 (ID: {id})")
    table.add_column("字段", style="cyan")
    table.add_column("值", style="green")

    table.add_row("ID", str(data.get("id", "")))
    table.add_row("标题", data.get("title", "")[:50])
    if verbose:
        table.add_row("内容", data.get("body", "")[:100])

    common.console.print(table)


@click.command(name="search")
@click.argument("query", required=False, default="")
@click.option("--limit", "-n", default=10, type=click.IntRange(1, 100), help="结果数量")
@common.structured_output_options
def search_cmd(query: str, limit: int, as_json: bool, as_yaml: bool):
    """搜索数据

    QUERY: 搜索关键词（可选）
    """
    from .. import client

    output_format = common.resolve_output_format(as_json=as_json, as_yaml=as_yaml)

    results = common.run_or_exit(
        client.search_examples(query, limit=limit),
        "搜索失败",
    )

    if common.emit_structured(
        {"items": results, "query": query, "limit": limit},
        output_format,
    ):
        return

    # Rich 渲染
    table = Table(title=f"🔍 搜索结果", border_style="blue")
    table.add_column("#", style="dim", width=4)
    table.add_column("ID", style="cyan", width=6)
    table.add_column("标题", max_width=40)

    for i, item in enumerate(results, 1):
        table.add_row(
            str(i),
            str(item.get("id", "")),
            item.get("title", "")[:40],
        )

    common.console.print(table)
```

**命令模式总结**：
1. 使用 Click 装饰器定义命令和参数
2. 添加 `@common.structured_output_options` 支持结构化输出
3. 使用 `common.run_or_exit()` 调用异步 API
4. 使用 `common.emit_structured()` 输出结构化数据
5. 使用 Rich 表格作为交互式输出

### 5.2 创建命令包初始化文件

创建 `my_cli/commands/__init__.py`：

```python
"""命令模块"""

from .example import get, search_cmd

__all__ = ["get", "search_cmd"]
```

---

## 六、实现 CLI 入口

### 6.1 创建版本信息

创建 `my_cli/__init__.py`：

```python
"""my-cli-tool - A modular CLI tool"""

try:
    from importlib.metadata import version

    __version__ = version("my-cli-tool")
except Exception:
    __version__ = "0.0.0"
```

### 6.2 创建 CLI 入口

创建 `my_cli/cli.py`：

```python
"""CLI 入口点"""

from __future__ import annotations

import click

from . import __version__
from .commands import example

@click.group()
@click.version_option(version=__version__, prog_name="mycli")
@click.option("-v", "--verbose", is_flag=True, help="启用调试日志")
def cli(verbose: bool):
    """mycli - 一个模块化的 CLI 工具 🛠️"""
    from .commands.common import setup_logging
    setup_logging(verbose)


# 注册命令
cli.add_command(example.get, name="get")
cli.add_command(example.search_cmd, name="search")


if __name__ == "__main__":
    cli()
```

**关键点**：
- `@click.group()` 创建命令组，支持子命令
- 所有命令通过 `cli.add_command()` 注册
- 使用 `setup_logging()` 统一配置日志

---

## 七、测试和使用

### 7.1 安装开发版本

```bash
# 在项目根目录
pip install -e .
```

### 7.2 测试命令

```bash
# 查看帮助
mycli --help

# 获取数据
mycli get 1

# 获取数据（JSON 格式）
mycli get 1 --json

# 获取数据（YAML 格式）
mycli get 1 --yaml

# 搜索数据
mycli search "test"

# 搜索数据（限制数量）
mycli search "test" --limit 5

# 启用调试日志
mycli -v get 1
```

### 7.3 测试结构化输出

```bash
# 管道输出 → 自动 YAML
mycli get 1 | cat

# 环境变量强制 YAML
OUTPUT=yaml mycli get 1

# 环境变量强制 JSON
OUTPUT=json mycli get 1
```

### 7.4 预期输出

**交互式输出**：
```
📄 数据详情 (ID: 1)
┏━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ 字段 ┃ 值                                       ┃
┡━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ID   │ 1                                        │
│ 标题 │ sunt aut facere repellat provident...   │
└──────┴──────────────────────────────────────────┘
```

**结构化输出**：
```yaml
ok: true
schema_version: '1'
data:
  id: 1
  title: sunt aut facere repellat provident
  body: quia et suscipit...
```

---

## 八、扩展指南

### 8.1 添加新命令

1. 在 `my_cli/commands/` 创建新文件，如 `my_cli/commands/user.py`
2. 实现命令函数（参考 `example.py`）
3. 在 `my_cli/commands/__init__.py` 导出
4. 在 `my_cli/cli.py` 注册命令

### 8.2 添加认证功能

参考 bilibili-cli 的 `auth.py`，实现：
1. 保存凭证到本地文件
2. 从浏览器提取 cookie
3. 二维码登录（可选）

### 8.3 添加更多输出格式

在 `formatter.py` 中添加：
- CSV 格式
- Markdown 表格
- 自定义模板

---

## 九、常见问题

### Q1: 为什么需要 asyncio.run()？

Click 命令是同步的，但很多 API 客户端（如 aiohttp）是异步的。`asyncio.run()` 桥接两者。

### Q2: 为什么使用 Schema Envelope？

统一响应格式，便于：
- AI Agent 解析
- 脚本处理
- 错误追踪

### Q3: 如何处理第三方 API 异常？

在 `client.py` 的 `_map_error()` 中统一映射，不暴露第三方异常给上层。

---

## 十、参考资料

- [Click 官方文档](https://click.palletsprojects.com/)
- [Rich 官方文档](https://rich.readthedocs.io/)
- [Python asyncio 文档](https://docs.python.org/3/library/asyncio.html)
- [bilibili-cli 源码](https://github.com/public-clis/bilibili-cli)

---

## 检查点

完成这份指南后，你应该能够：

- [ ] 理解 CLI 工具的分层架构
- [ ] 使用 Click 创建命令和参数
- [ ] 实现双模式输出（Rich + 结构化）
- [ ] 桥接异步 API 和同步 CLI
- [ ] 设计层次化的异常处理
- [ ] 扩展新命令和功能

如果你遇到问题，可以参考 [bilibili-cli](https://github.com/public-clis/bilibili-cli) 的完整实现。
