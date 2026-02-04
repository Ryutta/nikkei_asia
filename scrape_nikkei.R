# Load necessary libraries
# To install: install.packages(c("rvest", "jsonlite", "dplyr", "httr", "rmarkdown", "lubridate"))
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

# Function to extract news from Nikkei Asia (Headlines)
extract_news <- function() {
  url <- "https://asia.nikkei.com/"

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

  props <- data$props$pageProps
  all_articles <- list()

  # Helper to safely extract date
  # We look for common date fields
  extract_date <- function(item) {
    possible_fields <- c("date", "published", "publishedAt", "displayDate", "updated", "publishedDate", "updatedAt")
    for (f in possible_fields) {
      if (f %in% names(item)) {
        return(item[[f]])
      }
    }
    return(NA)
  }

  # 1. Homepage Latest Headlines
  if (!is.null(props$homepageLatestHeadlines$items)) {
    df <- props$homepageLatestHeadlines$items
    if ("name" %in% names(df) && "path" %in% names(df)) {
      # Try to find a date column in the dataframe
      date_col <- NA
      possible_fields <- c("date", "published", "publishedAt", "displayDate", "updated", "publishedDate", "updatedAt")
      for (f in possible_fields) {
        if (f %in% names(df)) {
          date_col <- f
          break
        }
      }

      temp_df <- df %>% select(title = name, path)
      if (!is.na(date_col)) {
        temp_df$date_raw <- df[[date_col]]
      } else {
        temp_df$date_raw <- NA
      }
      all_articles[[length(all_articles) + 1]] <- temp_df
    }
  }

  # 2. Extract from content blocks
  if (!is.null(props$data$blocks)) {
    blocks <- props$data$blocks
    if (nrow(blocks) > 0) {
      for (i in seq_len(nrow(blocks))) {
        if ("items" %in% names(blocks) && !is.null(blocks$items)) {
          items <- blocks$items[[i]]
          if (!is.null(items) && is.data.frame(items)) {
            temp_df <- NULL
            date_val <- NA

            # Identify Date Column
            possible_fields <- c("date", "published", "publishedAt", "displayDate", "updated", "publishedDate", "updatedAt")
            for (f in possible_fields) {
              if (f %in% names(items)) {
                date_val <- items[[f]]
                break
              }
            }

            if ("name" %in% names(items) && "path" %in% names(items)) {
              temp_df <- items %>% select(title = name, path)
            } else if ("headline" %in% names(items) && "url" %in% names(items)) {
              temp_df <- items %>% select(title = headline, path = url)
            }

            if (!is.null(temp_df)) {
              if (!is.null(date_val) && length(date_val) == nrow(temp_df)) {
                temp_df$date_raw <- date_val
              } else {
                temp_df$date_raw <- NA
              }
              all_articles[[length(all_articles) + 1]] <- temp_df
            }
          }
        }

        # Handling single headline blocks
        if ("headline" %in% names(blocks) && "headline_url" %in% names(blocks)) {
          title <- blocks$headline[i]
          path <- blocks$headline_url[i]
          # Try to find date in block level? Less likely, but let's check
          date_raw <- NA # Default

          if (!is.na(title) && !is.na(path) && title != "") {
            all_articles[[length(all_articles) + 1]] <- data.frame(title = title, path = path, date_raw = date_raw, stringsAsFactors = FALSE)
          }
        }
      }
    }
  }

  # 3. Most Read
  if (!is.null(props$mostReadArticles)) {
    df <- props$mostReadArticles
    if ("title" %in% names(df) && "path" %in% names(df)) {
       # Most Read usually doesn't show date on home, but let's check
      date_col <- NA
      possible_fields <- c("date", "published", "publishedAt", "displayDate", "updated", "publishedDate")
      for (f in possible_fields) {
        if (f %in% names(df)) {
          date_col <- f
          break
        }
      }

      temp_df <- df %>% select(title, path)
      if (!is.na(date_col)) {
        temp_df$date_raw <- df[[date_col]]
      } else {
        temp_df$date_raw <- NA
      }
      all_articles[[length(all_articles) + 1]] <- temp_df
    }
  }

  if (length(all_articles) > 0) {
    combined <- bind_rows(all_articles)
    combined <- combined %>% filter(!is.na(title) & !is.na(path) & title != "")

    # Normalize Link
    combined$link <- sapply(combined$path, function(p) {
      if (grepl("^http", p)) return(p)
      else if (grepl("^/", p)) return(paste0("https://asia.nikkei.com", p))
      else return(paste0("https://asia.nikkei.com/", p))
    })

    combined <- combined %>% distinct(link, .keep_all = TRUE) %>% select(title, link, date_raw)

    # Attempt to parse date
    # Format usually ISO or "October 26, 2023"
    # We use lubridate's parse_date_time which is very flexible
    combined$date <- NA
    if (!all(is.na(combined$date_raw))) {
      # Try parsing
      parsed_dates <- parse_date_time(combined$date_raw, orders = c("ymd", "ymd HMS", "mdy", "mdy HMS", "dmy", "dmy HMS", "ISO8601"))
      combined$date <- as.Date(parsed_dates)
    }

    return(combined)
  }
  return(NULL)
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
  body_node <- page %>% html_node(".c-article-body, [class*='article-body'], [class*='ArticleBody']")

  full_text <- ""
  if (length(body_node) > 0) {
    paragraphs <- body_node %>% html_nodes("p") %>% html_text()
    full_text <- paste(paragraphs, collapse = "\n\n")
  }

  if (nchar(full_text) < 100) {
    # Fallback to metadata description if body is empty
    meta_desc <- page %>% html_node("meta[name='description']") %>% html_attr("content")
    if (!is.na(meta_desc)) {
        full_text <- paste("[Body extraction failed. Description]:", meta_desc)
    }
  }

  if (full_text == "") {
    full_text <- "[Content extraction failed. Please check cookie or selector.]"
  }

  return(full_text)
}

# Function to generate RMarkdown and PDF report
generate_report <- function(articles_list, title_text, filename_base, cookie) {
    full_articles <- list()

    # Fetch content
    if (cookie != "") {
        for (i in 1:nrow(articles_list)) {
          title <- articles_list$title[i]
          link <- articles_list$link[i]

          text <- get_article_content(link, cookie)

          full_articles[[i]] <- list(title = title, link = link, text = text)
        }
    } else {
        # If no cookie, just list titles and links
         for (i in 1:nrow(articles_list)) {
          full_articles[[i]] <- list(title = articles_list$title[i], link = articles_list$link[i], text = "[Full text requires cookie]")
        }
    }

    # Generate RMarkdown file
    rmd_file <- paste0(filename_base, ".Rmd")
    pdf_file <- paste0(filename_base, ".pdf")

    # Create RMarkdown content
    rmd_content <- c(
      "---",
      paste0("title: \"", title_text, "\""),
      paste0("date: \"", Sys.Date(), "\""),
      "output: pdf_document",
      "---",
      "",
      paste0("# ", title_text),
      ""
    )

    for (article in full_articles) {
      rmd_content <- c(rmd_content,
        paste0("## ", article$title),
        paste0("**Link:** ", article$link),
        "",
        article$text,
        "",
        "\\newpage", # Page break
        ""
      )
    }

    writeLines(rmd_content, rmd_file)
    message("Created RMarkdown report: ", rmd_file)

    # Render to PDF
    message("Rendering PDF...")
    tryCatch({
      render(rmd_file, output_file = pdf_file, quiet = TRUE)
      message("Successfully generated PDF report: ", pdf_file)
    }, error = function(e) {
      message("Failed to generate PDF: ", e$message)
      # Fallback: Save as Markdown
      md_file <- paste0(filename_base, ".md")
      writeLines(rmd_content, md_file)
      message("Saved as Markdown instead: ", md_file)
    })
}


# Main Execution Flow
main <- function() {
  # 1. Get All Headlines
  all_news <- extract_news()

  if (is.null(all_news) || nrow(all_news) == 0) {
    message("No news found.")
    return()
  }

  message("Found ", nrow(all_news), " articles in total.")

  # --- Part 1: Top 10 Headlines (Legacy Behavior) ---
  message("\n--- Processing Top 10 Headlines ---")
  top10_list <- head(all_news, 10)

  # Save CSV
  write.csv(top10_list %>% select(title, link), "nikkei_news_top10.csv", row.names = FALSE)
  message("Saved headlines to nikkei_news_top10.csv")

  # Check Cookie
  cookie <- Sys.getenv("NIKKEI_COOKIE")
  if (cookie == "") {
    message("NOTE: NIKKEI_COOKIE environment variable is not set. Full text will not be available.")
  }

  # Generate PDF for Top 10
  generate_report(top10_list, "Nikkei Asia Top 10 News", "nikkei_full_report", cookie)


  # --- Part 2: Yesterday's Articles (New Feature) ---
  message("\n--- Processing Yesterday's Articles ---")

  yesterday <- Sys.Date() - 1
  message("Looking for articles dated: ", yesterday)

  # Filter for yesterday
  # We handle NAs by excluding them from this specific filter
  yesterday_news <- all_news %>% filter(!is.na(date) & date == yesterday)

  if (nrow(yesterday_news) > 0) {
      message("Found ", nrow(yesterday_news), " articles from yesterday.")

      # Filename with date
      filename_base <- paste0("nikkei_news_", yesterday)
      csv_filename <- paste0(filename_base, ".csv")

      # Save CSV
      write.csv(yesterday_news %>% select(title, link, date), csv_filename, row.names = FALSE)
      message("Saved yesterday's news to ", csv_filename)

      # Generate PDF
      generate_report(yesterday_news, paste0("Nikkei Asia News - ", yesterday), filename_base, cookie)

  } else {
      message("No articles found specifically dated ", yesterday, " in the scraped feed.")
      message("Note: The scraped feed is limited to the homepage/latest JSON. Older articles might require pagination (not implemented).")

      # Debug: Print dates found
      message("Dates found in feed: ", paste(unique(na.omit(all_news$date)), collapse=", "))
  }
}

# Execute
main()
