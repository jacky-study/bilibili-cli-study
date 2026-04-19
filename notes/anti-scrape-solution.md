---
article_id: OBA-939dur88
tags: [open-source, bilibili-cli, anti-scrape-solution.md, python, cli]
type: learning
updated_at: 2026-03-26
---

# 研究发现: bilibili-cli 的风控解决方案

> 通过额外 Cookie 字段、凭证 TTL 管理、浏览器 Cookie 提取和友好的错误处理，有效应对 Bilibili 的反爬机制

## 一、背景知识

### 1.1 Bilibili 的风控机制

Bilibili 使用多种手段检测和阻止爬虫：

| 机制 | 说明 |
|------|------|
| **HTTP 412** | 反爬触发时的响应码 |
| **Cookie 验证** | 需要 `buvid3`、`buvid4`、`dedeuserid` 等字段 |
| **请求频率限制** | 高频请求触发风控 |
| **SESSDATA 有效期** | 会话凭证有时效性 |

### 1.2 风控触发的影响

- API 请求返回 HTTP 412 错误
- 账号可能被临时限制
- 需要等待冷却或更换凭证

## 二、关键代码位置

| 文件 | 行号 | 说明 |
|------|------|------|
| `auth.py` | 33-34 | 额外 Cookie 字段定义（绕过 412） |
| `auth.py` | 36-38 | 凭证 TTL 配置（7天） |
| `auth.py` | 106-118 | 凭证过期检测 |
| `auth.py` | 175-261 | 浏览器 Cookie 提取 |
| `client.py` | 69-71 | HTTP 412 错误识别 |
| `exceptions.py` | 20-21 | RateLimitError 定义 |

## 三、解决方案详解

### 3.1 额外 Cookie 字段

**核心代码** (`auth.py`):

```python
# Required cookies for a valid Bilibili session
REQUIRED_COOKIES = {"SESSDATA"}

# Extra cookie fields that help bypass Bilibili's 412 anti-scraping checks
EXTRA_COOKIE_FIELDS = ("buvid3", "buvid4", "dedeuserid")
```

**工作原理**：

1. **buvid3**：浏览器唯一标识符，用于追踪用户设备
2. **buvid4**：设备指纹，增强设备识别
3. **dedeuserid**：用户 ID，关联账号信息

**为什么有效？**
- 这些字段模拟真实浏览器行为
- Bilibili 通过这些字段区分正常用户和爬虫
- 完整的 Cookie 组合降低被识别为爬虫的概率

**实现方式**：

```python
# 保存凭证时包含额外字段
def save_credential(credential: Credential):
    data = {
        "sessdata": credential.sessdata,
        "bili_jct": credential.bili_jct,
        "ac_time_value": credential.ac_time_value or "",
        "buvid3": credential.buvid3 or "",
        "buvid4": credential.buvid4 or "",
        "dedeuserid": credential.dedeuserid or "",
        "saved_at": time.time(),
    }
    CREDENTIAL_FILE.write_text(json.dumps(data, indent=2, ensure_ascii=False))
```

### 3.2 凭证 TTL 管理

**核心代码** (`auth.py`):

```python
# Credential TTL: warn and attempt refresh after 7 days
CREDENTIAL_TTL_DAYS = 7
_CREDENTIAL_TTL_SECONDS = CREDENTIAL_TTL_DAYS * 86400

def _is_credential_stale() -> bool:
    """Check if saved credential file is older than TTL."""
    if not CREDENTIAL_FILE.exists():
        return False
    try:
        data = json.loads(CREDENTIAL_FILE.read_text())
        saved_at = data.get("saved_at", 0)
        if not saved_at:
            return True  # Legacy file — treat as stale
        return (time.time() - saved_at) > _CREDENTIAL_TTL_SECONDS
    except (json.JSONDecodeError, OSError):
        return False
```

**自动刷新流程**：

```
┌─────────────────────────────────────────────┐
│  获取凭证                                    │
├─────────────────────────────────────────────┤
│  1. 加载保存的凭证                           │
│     ├─ 检查 TTL（7天）                       │
│     │   ├─ 过期 → 尝试从浏览器刷新           │
│     │   │   ├─ 刷新成功 → 保存并返回         │
│     │   │   └─ 刷新失败 → 验证现有凭证       │
│     │   └─ 未过期 → 验证现有凭证             │
│     │                                        │
│  2. 验证凭证                                 │
│     ├─ 有效 → 返回                           │
│     ├─ 无效 → 清除                           │
│     └─ 网络问题 → 返回凭证（尽力而为）       │
│                                              │
│  3. 浏览器 Cookie 提取（备用）               │
│     ├─ 提取成功 → 验证并保存                 │
│     └─ 提取失败 → 返回 None                  │
└─────────────────────────────────────────────┘
```

**为什么有效？**
- 避免使用过期凭证触发风控
- 自动刷新减少用户干预
- TTL 内保持稳定，减少 API 验证请求

### 3.3 浏览器 Cookie 提取

**核心代码** (`auth.py`):

```python
def _extract_browser_credential() -> Credential | None:
    """Extract Bilibili cookies from local browsers using browser-cookie3."""
    extract_script = '''
import json, sys
try:
    import browser_cookie3 as bc3
except ImportError:
    print(json.dumps({"error": "not_installed"}))
    sys.exit(0)

browsers = [
    ("Chrome", bc3.chrome),
    ("Firefox", bc3.firefox),
    ("Edge", bc3.edge),
    ("Brave", bc3.brave),
]

for name, loader in browsers:
    try:
        cj = loader(domain_name=".bilibili.com")
        cookies = {c.name: c.value for c in cj if "bilibili.com" in (c.domain or "")}
        if "SESSDATA" in cookies:
            print(json.dumps({"browser": name, "cookies": cookies}))
            sys.exit(0)
    except Exception:
        pass

print(json.dumps({"error": "no_cookies"}))
'''

    result = subprocess.run(
        [sys.executable, "-c", extract_script],
        capture_output=True,
        text=True,
        timeout=15,  # 15秒超时，避免浏览器锁定时卡住
    )
    # ... 解析结果
```

**关键设计**：

1. **子进程隔离**：在独立进程中运行，避免主程序卡死
2. **超时保护**：15 秒超时，避免浏览器锁定（Chrome SQLite 锁）导致卡住
3. **多浏览器支持**：尝试 Chrome、Firefox、Edge、Brave
4. **完整 Cookie 提取**：包括 `buvid3`、`buvid4`、`dedeuserid`

**为什么有效？**
- 浏览器中的 Cookie 是真实用户行为产生的
- 包含完整的设备指纹信息
- 模拟真实浏览器请求，降低被识别为爬虫的概率

### 3.4 错误识别和友好提示

**核心代码** (`client.py`):

```python
def _map_api_error(action: str, exc: Exception) -> BiliError:
    """Map third-party API exceptions into stable local exception types."""
    if isinstance(exc, ResponseCodeException):
        code = getattr(exc, "code", None)
        # Rate limit / anti-scraping
        if code in {-412, 412}:
            return RateLimitError(f"{action}: {exc}")
        # ... 其他错误映射
```

**用户提示** (`README.md`):

```markdown
- `HTTP 412` / `RateLimitError` — B站反爬触发，稍等后重试，或减小 `--max`
```

**错误处理流程**：

```
API 请求 → 捕获异常 → 识别错误类型
                        │
                        ├─ HTTP 412 → RateLimitError
                        │              │
                        │              └─ 提示用户：
                        │                 1. 等待后重试
                        │                 2. 减少请求量
                        │
                        ├─ HTTP 401 → AuthenticationError
                        │              │
                        │              └─ 提示用户重新登录
                        │
                        └─ 其他 → NetworkError / BiliError
```

## 四、设计亮点

### 1. **多层防护策略**

```
第一层：额外 Cookie 字段（buvid3/buvid4/dedeuserid）
    ↓ 被识别
第二层：凭证 TTL 管理（自动刷新过期凭证）
    ↓ 仍然触发
第三层：友好的错误处理（提示用户调整策略）
```

### 2. **真实用户行为模拟**

- 从浏览器提取 Cookie，而非手动配置
- 保留完整的设备指纹信息
- 自动刷新保持凭证新鲜度

### 3. **优雅降级**

```
浏览器 Cookie → 保存的凭证 → 提示用户登录
```

不强制要求所有字段，尽力而为。

### 4. **用户友好的错误提示**

- 明确告知是风控触发（HTTP 412）
- 提供具体的解决方案（等待/减少请求量）
- 结构化错误码便于自动化处理

## 五、可复用模式

### 5.1 风控 Cookie 配置模板

```python
# auth.py

# 核心认证字段
REQUIRED_COOKIES = {"session_token"}

# 风控绕过字段（根据目标平台调整）
ANTI_SCRAPE_FIELDS = (
    "device_id",      # 设备标识
    "fingerprint",    # 指纹
    "user_agent",     # UA
    "csrf_token",     # CSRF 令牌
)

def build_credential(cookies: dict) -> Credential:
    """构建包含风控字段的凭证"""
    return Credential(
        session_token=cookies.get("session_token"),
        device_id=cookies.get("device_id"),
        fingerprint=cookies.get("fingerprint"),
        user_agent=cookies.get("user_agent"),
        csrf_token=cookies.get("csrf_token"),
    )
```

### 5.2 TTL 管理模板

```python
# auth.py

import time
import json
from pathlib import Path

CREDENTIAL_TTL_DAYS = 7
CREDENTIAL_FILE = Path.home() / ".my-cli" / "credential.json"

def is_credential_stale() -> bool:
    """检查凭证是否过期"""
    if not CREDENTIAL_FILE.exists():
        return False

    try:
        data = json.loads(CREDENTIAL_FILE.read_text())
        saved_at = data.get("saved_at", 0)
        return (time.time() - saved_at) > (CREDENTIAL_TTL_DAYS * 86400)
    except (json.JSONDecodeError, OSError):
        return True

def save_credential(credential: Credential):
    """保存凭证并记录时间戳"""
    data = credential_to_dict(credential)
    data["saved_at"] = time.time()  # 关键：记录保存时间

    CREDENTIAL_FILE.parent.mkdir(parents=True, exist_ok=True)
    CREDENTIAL_FILE.write_text(json.dumps(data, indent=2))
    CREDENTIAL_FILE.chmod(0o600)  # 安全：仅所有者可读写
```

### 5.3 错误识别模板

```python
# client.py

def _map_api_error(action: str, exc: Exception) -> APIError:
    """映射第三方 API 异常到本地异常"""
    if isinstance(exc, ResponseCodeException):
        code = getattr(exc, "code", None)

        # 认证失败
        if code in {-101, -111, 401}:
            return AuthenticationError(f"{action}: {exc}")

        # 风控触发
        if code in {-412, 412, 429}:
            return RateLimitError(
                f"{action}: 风控触发，请稍后重试或减少请求频率"
            )

        # 资源不存在
        if code in {-404, 404}:
            return NotFoundError(f"{action}: {exc}")

        # 其他错误
        return APIError(f"{action}: [{code}] {exc}")

    # 网络错误
    if isinstance(exc, (NetworkException, aiohttp.ClientError)):
        return NetworkError(f"{action}: 网络请求失败")

    return APIError(f"{action}: {exc}")
```

## 六、最佳实践

### 1. **请求频率控制**

```python
import asyncio
import time
from functools import wraps

def rate_limit(calls_per_second: float = 2):
    """限流装饰器"""
    min_interval = 1.0 / calls_per_second
    last_called = [0.0]

    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            elapsed = time.time() - last_called[0]
            if elapsed < min_interval:
                await asyncio.sleep(min_interval - elapsed)

            result = await func(*args, **kwargs)
            last_called[0] = time.time()
            return result
        return wrapper
    return decorator

@rate_limit(calls_per_second=2)  # 每秒最多 2 次请求
async def fetch_data(id: str):
    # ...
```

### 2. **重试策略**

```python
import asyncio
import logging
from typing import TypeVar, Callable, Awaitable

T = TypeVar("T")
logger = logging.getLogger(__name__)

async def retry_with_backoff(
    func: Callable[[], Awaitable[T]],
    max_retries: int = 3,
    base_delay: float = 1.0,
    exceptions: tuple = (Exception,),
) -> T:
    """带指数退避的重试"""
    for attempt in range(max_retries):
        try:
            return await func()
        except exceptions as e:
            if attempt == max_retries - 1:
                raise

            delay = base_delay * (2 ** attempt)  # 指数退避
            logger.warning(
                f"{type(e).__name__}: {e}, "
                f"retrying in {delay:.1f}s "
                f"(attempt {attempt + 1}/{max_retries})"
            )
            await asyncio.sleep(delay)

    raise RuntimeError("Unreachable")
```

### 3. **用户提示最佳实践**

```python
# 错误提示模板
ERROR_MESSAGES = {
    "rate_limited": """
⚠️  请求频率过高，触发了风控

解决方案：
1. 等待 1-2 分钟后重试
2. 减少单次请求数量（使用 --max 参数）
3. 确保已登录（bili login）

如果问题持续，可能是 IP 被限制，请稍后再试。
""",
    "not_authenticated": """
⚠️  需要登录

解决方案：
1. 运行 bili login 扫码登录
2. 或确保已在浏览器登录 bilibili.com
""",
}
```

## 七、参考资料

- [HTTP 412 状态码](https://developer.mozilla.org/zh-CN/docs/Web/HTTP/Status/412)
- [bilibili-api-python 文档](https://github.com/Nemo2011/bilibili-api)
- [browser-cookie3 库](https://pypi.org/project/browser-cookie3/)
