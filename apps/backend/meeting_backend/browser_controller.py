import os
import shutil
import subprocess
from dataclasses import dataclass
from typing import Any, Dict, Optional


_DRIVER: Optional[Any] = None
COMMON_CHROMEDRIVER_PATHS = (
    "/opt/homebrew/bin/chromedriver",
    "/usr/local/bin/chromedriver",
)


@dataclass(frozen=True)
class BrowserResult:
    ok: bool
    message: str
    selenium_available: bool
    chromedriver_available: bool
    browser_session_active: bool = False

    def to_dict(self) -> Dict[str, Any]:
        return {
            "ok": self.ok,
            "message": self.message,
            "selenium_available": self.selenium_available,
            "chromedriver_available": self.chromedriver_available,
            "browser_session_active": self.browser_session_active,
        }


class BrowserController:
    def status(self) -> Dict[str, Any]:
        return BrowserResult(
            ok=selenium_available(),
            message=browser_status_message(),
            selenium_available=selenium_available(),
            chromedriver_available=chromedriver_available(),
            browser_session_active=_DRIVER is not None,
        ).to_dict()

    def open_url(self, url: str) -> Dict[str, Any]:
        clean_url = validate_url(url)
        try:
            driver = self._driver()
            driver.get(clean_url)
            return BrowserResult(
                ok=True,
                message="Opened Google Doc in ChromeDriver browser session.",
                selenium_available=True,
                chromedriver_available=chromedriver_available(),
                browser_session_active=True,
            ).to_dict()
        except Exception as error:
            if open_with_system_browser(clean_url):
                return BrowserResult(
                    ok=True,
                    message="Opened Google Doc with the system browser.",
                    selenium_available=selenium_available(),
                    chromedriver_available=chromedriver_available(),
                    browser_session_active=False,
                ).to_dict()
            return BrowserResult(
                ok=False,
                message="Browser open failed: {}".format(error),
                selenium_available=selenium_available(),
                chromedriver_available=chromedriver_available(),
                browser_session_active=False,
            ).to_dict()

    def scroll_to_bottom(self) -> Dict[str, Any]:
        driver = self._driver()
        driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
        return BrowserResult(
            ok=True,
            message="Scrolled browser view to bottom.",
            selenium_available=True,
            chromedriver_available=chromedriver_available(),
            browser_session_active=True,
        ).to_dict()

    def find_visible_text(self, text: str) -> Dict[str, Any]:
        query = text.strip()
        if not query:
            raise ValueError("Find text is empty")

        driver = self._driver()
        body = driver.find_element(selenium_by().TAG_NAME, "body")
        keys = selenium_keys()
        modifier = keys.COMMAND if os.uname().sysname == "Darwin" else keys.CONTROL
        body.send_keys(modifier, "f")
        body.send_keys(query)
        body.send_keys(keys.ENTER)
        return BrowserResult(
            ok=True,
            message="Sent browser find command for visible text.",
            selenium_available=True,
            chromedriver_available=chromedriver_available(),
            browser_session_active=True,
        ).to_dict()

    def _driver(self) -> Any:
        global _DRIVER
        if _DRIVER is not None:
            return _DRIVER

        webdriver = selenium_webdriver()
        options = webdriver.ChromeOptions()
        options.add_argument("--start-maximized")
        driver_path = resolve_chromedriver_path()
        if driver_path:
            service = selenium_chrome_service()(executable_path=driver_path)
            _DRIVER = webdriver.Chrome(service=service, options=options)
        else:
            _DRIVER = webdriver.Chrome(options=options)
        return _DRIVER


def validate_url(url: str) -> str:
    clean_url = url.strip()
    if not clean_url.startswith("https://docs.google.com/document/"):
        raise ValueError("Only Google Docs document URLs can be opened")
    return clean_url


def open_with_system_browser(url: str) -> bool:
    if os.uname().sysname != "Darwin":
        return False

    commands = [
        ["open", "-a", "Google Chrome", url],
        ["open", url],
    ]
    for command in commands:
        completed = subprocess.run(command, capture_output=True, text=True, check=False)
        if completed.returncode == 0:
            return True
    return False


def browser_status_message() -> str:
    if not selenium_available():
        return "Selenium is not installed. Browser open can use macOS open."
    if chromedriver_available():
        return "Selenium and ChromeDriver are available."
    return "Selenium is available. ChromeDriver was not found; set CHROMEDRIVER_PATH if Chrome does not launch."


def selenium_available() -> bool:
    try:
        selenium_webdriver()
        selenium_by()
        selenium_keys()
    except Exception:
        return False
    return True


def chromedriver_available() -> bool:
    return resolve_chromedriver_path() is not None


def resolve_chromedriver_path() -> Optional[str]:
    env_path = os.environ.get("CHROMEDRIVER_PATH", "").strip()
    if is_executable_file(env_path):
        return env_path

    path_match = shutil.which("chromedriver")
    if path_match:
        return path_match

    for candidate in COMMON_CHROMEDRIVER_PATHS:
        if is_executable_file(candidate):
            return candidate
    return None


def is_executable_file(path: str) -> bool:
    return bool(path) and os.path.isfile(path) and os.access(path, os.X_OK)


def selenium_webdriver() -> Any:
    from selenium import webdriver

    return webdriver


def selenium_chrome_service() -> Any:
    from selenium.webdriver.chrome.service import Service

    return Service


def selenium_by() -> Any:
    from selenium.webdriver.common.by import By

    return By


def selenium_keys() -> Any:
    from selenium.webdriver.common.keys import Keys

    return Keys
