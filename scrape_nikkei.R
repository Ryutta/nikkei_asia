# Load necessary libraries
# To install: install.packages(c("rvest", "jsonlite", "dplyr", "httr", "rmarkdown"))
if (!require("rvest")) install.packages("rvest")
if (!require("jsonlite")) install.packages("jsonlite")
if (!require("dplyr")) install.packages("dplyr")
if (!require("httr")) install.packages("httr")
if (!require("rmarkdown")) install.packages("rmarkdown")

library(rvest)
library(jsonlite)
library(dplyr)
library(httr)
library(rmarkdown)

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

  # 1. Homepage Latest Headlines
  if (!is.null(props$homepageLatestHeadlines$items)) {
    df <- props$homepageLatestHeadlines$items
    if ("name" %in% names(df) && "path" %in% names(df)) {
      all_articles[[length(all_articles) + 1]] <- df %>% select(title = name, path)
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
            if ("name" %in% names(items) && "path" %in% names(items)) {
              df <- items %>% select(title = name, path)
              all_articles[[length(all_articles) + 1]] <- df
            } else if ("headline" %in% names(items) && "url" %in% names(items)) {
              df <- items %>% select(title = headline, path = url)
              all_articles[[length(all_articles) + 1]] <- df
            }
          }
        }
        if ("headline" %in% names(blocks) && "headline_url" %in% names(blocks)) {
          title <- blocks$headline[i]
          path <- blocks$headline_url[i]
          if (!is.na(title) && !is.na(path) && title != "") {
            all_articles[[length(all_articles) + 1]] <- data.frame(title = title, path = path, stringsAsFactors = FALSE)
          }
        }
      }
    }
  }

  # 3. Most Read
  if (!is.null(props$mostReadArticles)) {
    df <- props$mostReadArticles
    if ("title" %in% names(df) && "path" %in% names(df)) {
      all_articles[[length(all_articles) + 1]] <- df %>% select(title, path)
    }
  }

  if (length(all_articles) > 0) {
    combined <- bind_rows(all_articles)
    combined <- combined %>% filter(!is.na(title) & !is.na(path) & title != "")
    combined$link <- sapply(combined$path, function(p) {
      if (grepl("^http", p)) return(p)
      else if (grepl("^/", p)) return(paste0("https://asia.nikkei.com", p))
      else return(paste0("https://asia.nikkei.com/", p))
    })
    combined <- combined %>% distinct(link, .keep_all = TRUE) %>% select(title, link)
    return(head(combined, 10))
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
  # Strategy 1: Look for common article body classes
  # .c-article-body is common in Nikkei Asia
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
        json_data <- fromJSON(html_text(script_node))
        # Navigate to content - this path is a guess based on common props structure, needs verification
        # Usually props -> pageProps -> currentArticle -> content -> body
        # Or props -> pageProps -> article -> content
        # We will try a recursive search or just dump specific fields if found
        # For now, let's keep it simple. If HTML fails, we might be out of luck without specific JSON path.
        message("HTML body extraction failed/empty. JSON fallback not fully implemented.")
      }, error = function(e) {})
    }
  }

  if (full_text == "") {
    full_text <- "[Content extraction failed. Please check cookie or selector.]"
  }

  return(full_text)
}

# Main Execution Flow
main <- function() {
  # 1. Get Headlines
  news_list <- extract_news()

  if (is.null(news_list)) {
    message("No news found.")
    return()
  }

  # Always save the CSV first (as per original functionality)
  write.csv(news_list, "nikkei_news_top10.csv", row.names = FALSE)
  message("Saved headlines to nikkei_news_top10.csv")

  # 2. Check for Cookie for Full Text
  cookie <- Sys.getenv("NIKKEI_COOKIE")

  if (cookie == "") {
    message("NOTE: NIKKEI_COOKIE environment variable is not set.")
    message("Skipping full text extraction. Only headlines are saved.")
    message("To get full text, set NIKKEI_COOKIE with your session cookie.")
  } else {
    message("NIKKEI_COOKIE found. Starting full text extraction...")

    # Prepare data for report
    full_articles <- list()

    for (i in 1:nrow(news_list)) {
      title <- news_list$title[i]
      link <- news_list$link[i]

      text <- get_article_content(link, cookie)

      full_articles[[i]] <- list(title = title, link = link, text = text)
    }

    # Generate RMarkdown file
    rmd_file <- "nikkei_full_report.Rmd"
    pdf_file <- "nikkei_full_report.pdf"

    # Create RMarkdown content
    rmd_content <- c(
      "---",
      "title: \"Nikkei Asia Full News Report\"",
      paste0("date: \"", Sys.Date(), "\""),
      "output: pdf_document",
      "---",
      "",
      "# Top 10 Articles",
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
      message("This might be due to missing 'pandoc' or LaTeX engine.")
      message("You can still use the generated .Rmd file or converting it to another format.")

      # Fallback: Save as Markdown
      md_file <- "nikkei_full_report.md"
      # Just rename or use the Rmd content as MD (strip YAML header if needed, but Rmd is MD compatible)
      writeLines(rmd_content, md_file)
      message("Saved as Markdown instead: ", md_file)
    })
  }
}

# Execute
main()
