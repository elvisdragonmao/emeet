import os
import shutil
import subprocess
from dataclasses import dataclass
from typing import Any, Dict, Optional


_DRIVER: Optional[Any] = None


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
                    message=(
                        "Opened Google Doc with the system browser. "
                        "Install Selenium and ChromeDriver to enable scroll/find."
                    ),
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
    if selenium_available():
        return "Selenium is available. ChromeDriver or Selenium Manager may launch Chrome."
    return "Selenium is not installed. Browser open can use macOS open, but scroll/find are unavailable."


def selenium_available() -> bool:
    try:
        selenium_webdriver()
        selenium_by()
        selenium_keys()
    except Exception:
        return False
    return True


def chromedriver_available() -> bool:
    return shutil.which("chromedriver") is not None


def selenium_webdriver() -> Any:
    from selenium import webdriver

    return webdriver


def selenium_by() -> Any:
    from selenium.webdriver.common.by import By

    return By


def selenium_keys() -> Any:
    from selenium.webdriver.common.keys import Keys

    return Keys
