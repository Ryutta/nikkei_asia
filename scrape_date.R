# Load necessary libraries
if (!require("rvest")) install.packages("rvest", repos = "https://cloud.r-project.org")
if (!require("jsonlite")) install.packages("jsonlite", repos = "https://cloud.r-project.org")
if (!require("dplyr")) install.packages("dplyr", repos = "https://cloud.r-project.org")
if (!require("httr")) install.packages("httr", repos = "https://cloud.r-project.org")
if (!require("rmarkdown")) install.packages("rmarkdown", repos = "https://cloud.r-project.org")
if (!require("lubridate")) install.packages("lubridate", repos = "https://cloud.r-project.org")

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

# Function to fetch news for a specific date using latestheadlines URL
scrape_news_by_date <- function(target_date_str) {
  target_date <- tryCatch(ymd(target_date_str), error = function(e) NULL)

  if (is.na(target_date)) {
    message("Invalid date format. Please use YYYYMMDD.")
    return(NULL)
  }

  formatted_date <- format(target_date, "%Y-%m-%d")
  all_articles_df <- data.frame()
  seen_links <- c()
  
  page_num <- 1
  keep_going <- TRUE
  max_pages <- 20 # Safety limit
  
  # User-Agent to avoid rejection
  ua <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"

  while(keep_going && page_num <= max_pages) {
      url <- paste0("https://asia.nikkei.com/latestheadlines?date=", formatted_date, "&page=", page_num)
      message("Fetching page ", page_num, " headlines for: ", formatted_date, " from ", url)

      session <- tryCatch(
        session(url, user_agent(ua)),
        error = function(e) {
          message("Failed to create session: ", e$message)
          return(NULL)
        }
      )

      if (is.null(session)) break

      webpage <- read_html(session)
      
      script_node <- webpage %>% html_node("#__NEXT_DATA__")
      if (length(script_node) == 0) {
        message("Could not find data script tag on page ", page_num, ".")
        
        # Debugging: Save the failed HTML to a file
        debug_filename <- paste0("debug_failed_", target_date_str, "_page", page_num, ".html")
        write_xml(webpage, debug_filename)
        message("Saved page content to ", debug_filename, " for inspection.")
        
        break
      }

      json_content <- html_text(script_node)
      data <- tryCatch(fromJSON(json_content), error = function(e) {
        message("Failed to parse JSON: ", e$message)
        return(NULL)
      })

      if (is.null(data)) break

      # Navigate to latestHeadlinesData items
      items <- data$props$pageProps$latestHeadlinesData$items

      if (is.null(items) || length(items) == 0) {
        message("No more items found on page ", page_num)
        break
      }
      
      # If items is a list of lists or not a dataframe, try to bind it
      if (!is.data.frame(items) && is.list(items)) {
         items <- tryCatch(bind_rows(items), error = function(e) NULL)
      }

      if (is.null(items) || nrow(items) == 0) {
          message("Items list is empty on page ", page_num)
          break
      }

      page_articles <- list()
      new_items_found <- FALSE

      for (i in 1:nrow(items)) {
        path <- items$path[i]
        link <- ifelse(grepl("^http", path), path, paste0("https://asia.nikkei.com", path))
        
        # Check duplication BEFORE processing date (optimization)
        if (link %in% seen_links) {
            next
        }
        
        title <- items$name[i]
        timestamp <- items$displayDate[i] 
        
        # Nikkei uses JST for the date filter in URL.
        item_date_obj <- as.POSIXct(timestamp, origin="1970-01-01", tz="Asia/Tokyo")
        item_date <- as.Date(item_date_obj)

        if (item_date == target_date) {
            page_articles[[length(page_articles) + 1]] <- data.frame(
              title = title,
              link = link,
              date = as.character(item_date),
              stringsAsFactors = FALSE
            )
            seen_links <- c(seen_links, link)
            new_items_found <- TRUE
        }
      }

      if (length(page_articles) > 0) {
        page_df <- bind_rows(page_articles)
        all_articles_df <- bind_rows(all_articles_df, page_df)
      }
      
      if (!new_items_found) {
          message("No new items found on page ", page_num, ". Stopping pagination.")
          break
      }
      
      page_num <- page_num + 1
      Sys.sleep(1) # Politeness
  }

  if (nrow(all_articles_df) > 0) {
    return(all_articles_df)
  } else {
    message("No articles matched the exact date ", target_date)
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

  # Final distinct check just in case
  news_list <- news_list %>% distinct(link, .keep_all = TRUE)
  
  message("Found ", nrow(news_list), " articles.")

  # Save Headlines CSV
  csv_filename <- paste0("nikkei_news_", target_date_str, ".csv")
  write.csv(news_list, csv_filename, row.names = FALSE)
  message("Saved headlines to ", csv_filename)

  # Full Text Extraction
  cookie <- Sys.getenv("NIKKEI_COOKIE")

  if (cookie == "") {
    # Try reading from cookie.txt if env var not set
    if (file.exists("cookie.txt")) {
        cookie <- readLines("cookie.txt", n = 1)
        message("Loaded cookie from cookie.txt")
    }
  }

  if (cookie == "") {
    message("NOTE: NIKKEI_COOKIE environment variable is not set and cookie.txt not found.")
    message("Skipping full text extraction.")
  } else {
    message("Cookie found. Starting full text extraction...")

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
