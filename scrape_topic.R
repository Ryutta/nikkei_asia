# Load necessary libraries
if (!require("rvest")) install.packages("rvest")
if (!require("jsonlite")) install.packages("jsonlite")
if (!require("dplyr")) install.packages("dplyr")
if (!require("httr")) install.packages("httr")

library(rvest)
library(jsonlite)
library(dplyr)
library(httr)

# --- Configuration ---
# You can change these variables to scrape different topics or change the number of articles
TARGET_URL <- "https://asia.nikkei.com/politics/japan-election"
ARTICLE_COUNT <- 20
# ---------------------

# Function to extract news from a topic page
extract_topic_news <- function(url, count) {
  message("Fetching topic page: ", url)

  # Fetch the webpage
  webpage <- tryCatch(read_html(url), error = function(e) {
    message("Failed to fetch URL: ", e$message)
    return(NULL)
  })

  if (is.null(webpage)) return(NULL)

  # Extract the __NEXT_DATA__ script
  script_node <- webpage %>% html_node("#__NEXT_DATA__")
  if (length(script_node) == 0) {
    message("Could not find data script tag.")
    return(NULL)
  }

  json_content <- html_text(script_node)
  data <- tryCatch(fromJSON(json_content), error = function(e) {
    message("Failed to parse JSON: ", e$message)
    return(NULL)
  })

  if (is.null(data)) return(NULL)

  # Navigate to the stream data
  # Based on analysis: props -> pageProps -> data -> stream
  stream <- data$props$pageProps$data$stream

  if (is.null(stream)) {
    message("No article stream found in the page data.")
    return(NULL)
  }

  # Ensure it's a data frame
  if (!is.data.frame(stream)) {
    # If it's a list, try to bind rows, but usually fromJSON returns a DF for array of objects
    if (is.list(stream)) {
      # It might be a list of lists if structure varies, but let's assume simple case first
      message("Stream is a list, attempting to convert...")
      # This part depends on actual structure if not DF
    }
  }

  articles <- stream

  # Normalize columns
  if ("headline" %in% names(articles)) {
    articles <- articles %>% rename(title = headline)
  }

  if (!"url" %in% names(articles) && "path" %in% names(articles)) {
    articles$url <- paste0("https://asia.nikkei.com", articles$path)
  }

  if (!("title" %in% names(articles)) || !("url" %in% names(articles))) {
     message("Could not find title or url in stream data.")
     return(NULL)
  }

  # Select and limit
  result <- articles %>%
    select(title, url) %>%
    head(count)

  return(result)
}

# Function to fetch full article content using cookie
get_article_content <- function(url, cookie_string) {
  Sys.sleep(1) # Politeness
  message("Fetching full text for: ", url)

  # Use httr to fetch with cookie
  response <- tryCatch(
    GET(url, add_headers(Cookie = cookie_string, `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")),
    error = function(e) {
      message("Error fetching ", url, ": ", e$message)
      return(NULL)
    }
  )

  if (is.null(response) || status_code(response) != 200) {
    message("Failed to fetch (Status ", status_code(response), "): ", url)
    return(NULL)
  }

  page_content <- content(response, "text", encoding = "UTF-8")
  page <- read_html(page_content)

  # Attempt to extract article body
  # Strategy 1: Look for common article body classes
  body_node <- page %>% html_node(".c-article-body, [class*='article-body'], [class*='ArticleBody']")

  full_text <- ""
  if (length(body_node) > 0) {
    # Extract text from paragraphs to preserve some structure
    paragraphs <- body_node %>% html_nodes("p") %>% html_text()
    full_text <- paste(paragraphs, collapse = "\n\n")
  }

  # Strategy 2: Fallback to __NEXT_DATA__ if HTML extraction failed or returned empty
  if (nchar(full_text) < 100) {
    script_node <- page %>% html_node("#__NEXT_DATA__")
    if (length(script_node) > 0) {
      tryCatch({
        # Simple extraction attempt if structured data is available
        # This is kept minimal as per original script
        message("HTML body extraction failed/empty.")
      }, error = function(e) {})
    }
  }

  if (full_text == "") {
    full_text <- "[Content extraction failed. Please check cookie or selector.]"
  }

  return(full_text)
}

main <- function() {
  # 1. Get Articles
  news_list <- extract_topic_news(TARGET_URL, ARTICLE_COUNT)

  if (is.null(news_list) || nrow(news_list) == 0) {
    message("No news found.")
    return()
  }

  message(paste("Found", nrow(news_list), "articles."))

  # 2. Check for Cookie for Full Text
  cookie <- Sys.getenv("NIKKEI_COOKIE")

  if (cookie == "") {
    message("NOTE: NIKKEI_COOKIE environment variable is not set.")
    message("Skipping full text extraction. Only links are saved.")
  } else {
    message("NIKKEI_COOKIE found. Starting full text extraction...")
  }

  # 3. Fetch Content and Build Markdown
  today_str <- format(Sys.Date(), "%Y-%m-%d")
  filename <- paste0("nikkei_topic_", today_str, ".md")

  md_content <- c(
    paste0("# Nikkei Asia Topic Report: ", TARGET_URL),
    paste0("Date: ", today_str),
    "",
    "---",
    ""
  )

  for (i in 1:nrow(news_list)) {
    title <- news_list$title[i]
    link <- news_list$url[i]

    md_content <- c(md_content, paste0("## ", i, ". ", title))
    md_content <- c(md_content, paste0("**Link:** ", link), "")

    if (cookie != "") {
      text <- get_article_content(link, cookie)
      md_content <- c(md_content, text, "")
    } else {
       md_content <- c(md_content, "[Full text requires NIKKEI_COOKIE]", "")
    }

    md_content <- c(md_content, "---", "")
  }

  writeLines(md_content, filename)
  message("Saved report to: ", filename)

  # Also save CSV for reference
  csv_filename <- paste0("nikkei_topic_", today_str, ".csv")
  write.csv(news_list, csv_filename, row.names = FALSE)
  message("Saved metadata to: ", csv_filename)
}

main()
