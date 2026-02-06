# Load necessary libraries
options(repos = c(CRAN = "https://cloud.r-project.org"))

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

# Function to search Nikkei Asia
search_nikkei <- function(keyword) {
  # URL encode the keyword
  encoded_keyword <- URLencode(keyword)
  url <- paste0("https://asia.nikkei.com/search?query=", encoded_keyword)

  message("Searching for: ", keyword)
  message("URL: ", url)

  # Fetch the webpage with a user agent
  response <- tryCatch(
    GET(url, add_headers(`User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")),
    error = function(e) {
      message("Failed to fetch URL: ", e$message)
      return(NULL)
    }
  )

  if (is.null(response) || status_code(response) != 200) {
    message("Failed to fetch search page (Status ", status_code(response), ")")
    return(NULL)
  }

  page_content <- content(response, "text", encoding = "UTF-8")
  webpage <- read_html(page_content)

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

  # Navigate to search results
  # Path: props -> pageProps -> data -> result
  results <- NULL
  if (!is.null(data$props$pageProps$data$result)) {
    results <- data$props$pageProps$data$result
  }

  if (is.null(results) || length(results) == 0) {
    message("No results found for keyword: ", keyword)
    return(NULL)
  }

  # Normalize data
  # We expect: headline, path, displayDate
  if (is.data.frame(results)) {
    df <- results %>%
      select(title = headline, path, date = displayDate) %>%
      mutate(
        link = sapply(path, function(p) {
          if (grepl("^http", p)) return(p)
          else return(paste0("https://asia.nikkei.com", p))
        })
      ) %>%
      select(title, link, date) %>%
      arrange(desc(date))

    # Return top 10
    return(head(df, 10))
  } else {
    message("Unexpected results format.")
    return(NULL)
  }
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
        # Parsing JSON might be complex given the structure varies, but we leave the placeholder logic
        # or minimal fallback if available.
      }, error = function(e) {})
    }
  }

  if (full_text == "") {
    full_text <- "[Content extraction failed. Please check cookie or selector.]"
  }

  return(full_text)
}

# Main execution
args <- commandArgs(trailingOnly = TRUE)

if (length(args) > 0) {
  keyword <- args[1]
} else {
  message("No keyword provided. Usage: Rscript search_nikkei.R <keyword>")
  # Default keyword for demonstration/testing
  keyword <- "Toyota"
  message("Defaulting to keyword: ", keyword)
}

results <- search_nikkei(keyword)

if (!is.null(results)) {
  print(results)
  write.csv(results, "search_results.csv", row.names = FALSE)
  message("Saved top 10 results to search_results.csv")

  # Check for cookie and generate report
  cookie <- Sys.getenv("NIKKEI_COOKIE")

  if (cookie == "") {
    message("NOTE: NIKKEI_COOKIE environment variable is not set.")
    message("Skipping full text extraction and report generation.")
    message("To get full text reports, set NIKKEI_COOKIE with your session cookie.")
  } else {
    message("NIKKEI_COOKIE found. Starting full text extraction for report...")

    full_articles <- list()

    # Iterate through results (df)
    for (i in 1:nrow(results)) {
      title <- results$title[i]
      link <- results$link[i]

      text <- get_article_content(link, cookie)

      full_articles[[i]] <- list(title = title, link = link, text = text)
    }

    # Generate RMarkdown file
    # Clean keyword for filename
    safe_keyword <- gsub("[^a-zA-Z0-9]", "_", keyword)
    rmd_file <- paste0("search_report_", safe_keyword, ".Rmd")
    pdf_file <- paste0("search_report_", safe_keyword, ".pdf")

    # Create RMarkdown content
    rmd_content <- c(
      "---",
      paste0("title: \"Nikkei Asia Search Report: ", keyword, "\""),
      paste0("date: \"", Sys.Date(), "\""),
      "output: pdf_document",
      "---",
      "",
      "# Search Results",
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
      md_file <- paste0("search_report_", safe_keyword, ".md")
      writeLines(rmd_content, md_file)
      message("Saved as Markdown instead: ", md_file)
    })
  }
}
