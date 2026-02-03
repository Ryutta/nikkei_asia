import os
import subprocess
import time
import sys
from dotenv import load_dotenv
from playwright.sync_api import sync_playwright

# Load environment variables
load_dotenv()

# Configuration
NIKKEI_COOKIE = os.getenv("NIKKEI_COOKIE")
NOTEBOOK_URL = os.getenv("NOTEBOOK_URL")
OUTPUT_PDF = "nikkei_full_report.pdf"
AUTH_FILE = "auth.json"  # To store session cookies for NotebookLM

def run_scraper():
    """Runs the R script to scrape Nikkei Asia."""
    print("--- Starting Scraper ---")
    if not NIKKEI_COOKIE:
        print("WARNING: NIKKEI_COOKIE is not set. Full text might not be extracted.")

    # Check if R is installed
    try:
        subprocess.run(["Rscript", "--version"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except FileNotFoundError:
        print("Error: R is not installed or not in PATH.")
        sys.exit(1)

    # Run the script
    try:
        result = subprocess.run(["Rscript", "scrape_nikkei.R"], check=True)
        if result.returncode == 0:
            print("Scraper finished successfully.")
        else:
            print("Scraper failed.")
            sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"Error running script: {e}")
        sys.exit(1)

    # Check if output exists
    if not os.path.exists(OUTPUT_PDF):
        # Fallback to MD if PDF failed
        if os.path.exists("nikkei_full_report.md"):
            print("PDF generation failed, but Markdown exists. Using Markdown.")
            return "nikkei_full_report.md"
        else:
            print("Error: Output file not found.")
            sys.exit(1)

    return OUTPUT_PDF

def upload_to_notebooklm(file_path):
    """Uploads the generated file to NotebookLM using Playwright."""
    print("--- Starting NotebookLM Upload ---")

    if not NOTEBOOK_URL:
        print("Error: NOTEBOOK_URL is not set in .env file.")
        print("Please create a .env file with NOTEBOOK_URL=https://notebooklm.google.com/notebook/...")
        sys.exit(1)

    with sync_playwright() as p:
        # Launch browser (Headful so user can see what's happening)
        browser = p.chromium.launch(headless=False)

        # Create context (load auth state if exists)
        if os.path.exists(AUTH_FILE):
            print(f"Loading session from {AUTH_FILE}...")
            context = browser.new_context(storage_state=AUTH_FILE)
        else:
            print("No saved session found. You may need to log in.")
            context = browser.new_context()

        page = context.new_page()

        print(f"Navigating to {NOTEBOOK_URL}...")
        page.goto(NOTEBOOK_URL)

        # Check for login redirect
        if "accounts.google.com" in page.url:
            print("Please log in to your Google account in the browser window.")
            print("Waiting for you to reach NotebookLM...")
            try:
                # Wait until we are back on notebooklm
                page.wait_for_url("**/notebook/**", timeout=300000) # 5 minutes to login
                # Save state
                context.storage_state(path=AUTH_FILE)
                print("Login successful! Session saved.")
            except Exception:
                print("Timed out waiting for login.")
                return

        # Wait for the interface to load
        print("Waiting for interface...")
        try:
            # Look for the "Add source" area.
            # Note: Selectors are brittle. We look for generic text or aria-labels.
            # Usually there is a plus button or "Add source" text.

            # Strategy: specific known selectors for NotebookLM (as of late 2023/early 2024)
            # This might change, so we try a few things.

            # 1. Look for 'Add source' text or button
            # The UI often has a big "Add source" button on the left sidebar.

            # Helper to find and click
            # We wait for the file input to be available or the button to trigger it.

            # In NotebookLM, usually you click "Add source" -> "PDF / Text file" -> opens system dialog.
            # Playwright handles system dialog via set_input_files on the input[type=file] element.

            # Often the input element exists but is hidden.
            # Let's try to make it visible or just set it.

            # Waiting for the page to stabilize
            page.wait_for_load_state("networkidle")

            # Try to find the file input directly first
            file_input = page.query_selector("input[type='file']")

            if not file_input:
                print("File input not found directly. Attempting to open 'Add Source' menu...")
                # Try clicking "Add source" or the Plus icon
                # Common classes or aria-labels
                # We'll try a text search for "Add source"
                page.get_by_text("Add source", exact=False).first.click()
                time.sleep(1) # Wait for animation/popover

                # Now check for file input again or "PDF" button
                file_input = page.query_selector("input[type='file']")

                if not file_input:
                    # Maybe we need to click "PDF" or "File" in the menu
                    page.get_by_text("PDF", exact=False).first.click()
                    # Now input should be there
                    file_input = page.query_selector("input[type='file']")

            if file_input:
                print(f"Uploading {file_path}...")
                file_input.set_input_files(file_path)
                print("File selected. Uploading...")

                # Wait for upload to process?
                # usually there's a spinner.
                time.sleep(5)
                print("Upload initiated.")
            else:
                print("Could not find file upload input. The UI might have changed.")
                print("Please upload the file manually: " + os.path.abspath(file_path))
                time.sleep(10) # Give user time to see

        except Exception as e:
            print(f"Automation error: {e}")
            print("Please upload the file manually.")

        print("Closing browser in 5 seconds...")
        time.sleep(5)

        # Save state again just in case
        context.storage_state(path=AUTH_FILE)
        browser.close()

if __name__ == "__main__":
    file_path = run_scraper()
    upload_to_notebooklm(file_path)
