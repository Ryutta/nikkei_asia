# Load necessary libraries
if (!require("rvest")) install.packages("rvest")
if (!require("jsonlite")) install.packages("jsonlite")
if (!require("dplyr")) install.packages("dplyr")
if (!require("httr")) install.packages("httr")
if (!require("rmarkdown")) install.packages("rmarkdown")
if (!require("lubridate")) install.packages("lubridate")

library(rvest)
library(jsonlite)
library(dplyr)
library(httr)
library(rmarkdown)
library(lubridate)

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
    paragraphs <- body_node %>% html_nodes("p") %>% html_text()
    full_text <- paste(paragraphs, collapse = "\n\n")
  }

  if (full_text == "") {
    full_text <- "[Content extraction failed. Please check cookie or selector.]"
  }

  return(full_text)
}

# Function to fetch news for a specific date
scrape_news_by_date <- function(target_date_str) {
  target_date <- tryCatch(ymd(target_date_str), error = function(e) NULL)

  if (is.na(target_date)) {
    message("Invalid date format. Please use YYYYMMDD.")
    return(NULL)
  }

  message("Searching for news on: ", target_date)

  all_articles <- list()
  page_num <- 1
  stop_search <- FALSE
  max_pages <- 50 # Safety limit

  while (!stop_search && page_num <= max_pages) {
    # We use 'query=news' as a generic search term because empty queries return no results.
    # We explicitly sort by 'newest' to ensure we can stop when we hit older dates.
    url <- paste0("https://asia.nikkei.com/search?query=news&sortBy=newest&page=", page_num)
    message("Fetching page: ", page_num)

    webpage <- tryCatch(read_html(url), error = function(e) {
      message("Failed to fetch URL: ", e$message)
      return(NULL)
    })

    if (is.null(webpage)) break

    script_node <- webpage %>% html_node("#__NEXT_DATA__")
    if (length(script_node) == 0) {
      message("Could not find data script tag.")
      break
    }

    json_content <- html_text(script_node)
    data <- tryCatch(fromJSON(json_content), error = function(e) {
      message("Failed to parse JSON: ", e$message)
      return(NULL)
    })

    if (is.null(data)) break

    props <- data$props$pageProps$data
    items <- props$result

    if (is.null(items) || length(items) == 0) {
      message("No items found on page ", page_num)
      break
    }

    # Process items
    for (i in 1:nrow(items)) {
      item_date_str <- items$displayDate[i]

      # Try parsing date with multiple formats (ISO 8601 is standard for API, but being robust)
      item_date <- tryCatch({
        as.Date(ymd_hms(item_date_str))
      }, error = function(e) {
        tryCatch(as.Date(ymd(item_date_str)), error = function(e) NA)
      })

      if (is.na(item_date)) next

      if (item_date == target_date) {
        # Valid article
        title <- items$headline[i]
        path <- items$path[i]
        link <- ifelse(grepl("^http", path), path, paste0("https://asia.nikkei.com", path))

        all_articles[[length(all_articles) + 1]] <- data.frame(
          title = title,
          link = link,
          date = as.character(item_date),
          stringsAsFactors = FALSE
        )
      } else if (item_date < target_date) {
        # Passed the target date (assuming sorted by date DESC)
        stop_search <- TRUE
        # Continue to process remaining items on this page just in case sorting is slightly off?
        # Usually search results are strictly sorted by date.
        # But let's check a few more just in case.
        # Actually, if we see a date older than target_date, usually we can stop page iteration.
        # But let's be safe and check all items on *this* page, then stop.
      }
    }

    if (stop_search) break
    page_num <- page_num + 1
    Sys.sleep(1) # Politeness
  }

  if (length(all_articles) > 0) {
    return(bind_rows(all_articles))
  } else {
    return(NULL)
  }
}

# Main Execution Flow
main <- function() {
  args <- commandArgs(trailingOnly = TRUE)

  if (length(args) == 0) {
    message("Usage: Rscript scrape_date.R <YYYYMMDD>")
    return()
  }

  target_date_str <- args[1]
  news_list <- scrape_news_by_date(target_date_str)

  if (is.null(news_list)) {
    message("No news found for date: ", target_date_str)
    return()
  }

  # Clean duplicates
  news_list <- news_list %>% distinct(link, .keep_all = TRUE)

  # Save Headlines CSV
  csv_filename <- paste0("nikkei_news_", target_date_str, ".csv")
  write.csv(news_list, csv_filename, row.names = FALSE)
  message("Saved headlines to ", csv_filename)

  # Full Text Extraction
  cookie <- Sys.getenv("NIKKEI_COOKIE")

  if (cookie == "") {
    message("NOTE: NIKKEI_COOKIE environment variable is not set.")
    message("Skipping full text extraction.")
  } else {
    message("NIKKEI_COOKIE found. Starting full text extraction...")

    full_articles <- list()

    for (i in 1:nrow(news_list)) {
      title <- news_list$title[i]
      link <- news_list$link[i]
      date_val <- news_list$date[i]

      text <- get_article_content(link, cookie)
      full_articles[[i]] <- list(title = title, link = link, date = date_val, text = text)
    }

    # Generate Markdown Report
    md_filename <- paste0("nikkei_news_", target_date_str, ".md")

    md_content <- c(
      paste0("# Nikkei Asia News Report - ", target_date_str),
      "",
      paste0("**Generated on:** ", Sys.Date()),
      "",
      "---",
      ""
    )

    for (article in full_articles) {
      md_content <- c(md_content,
        paste0("## ", article$title),
        paste0("**Date:** ", article$date),
        paste0("**Link:** ", article$link),
        "",
        article$text,
        "",
        "---",
        ""
      )
    }

    writeLines(md_content, md_filename)
    message("Created Markdown report: ", md_filename)
  }
}

main()
