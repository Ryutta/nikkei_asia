# Load necessary libraries
options(repos = c(CRAN = "https://cloud.r-project.org"))

if (!require("rvest")) install.packages("rvest")
if (!require("jsonlite")) install.packages("jsonlite")
if (!require("dplyr")) install.packages("dplyr")
if (!require("httr")) install.packages("httr")

library(rvest)
library(jsonlite)
library(dplyr)
library(httr)

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

# Main execution
args <- commandArgs(trailingOnly = TRUE)

if (length(args) > 0) {
  keyword <- args[1]
} else {
  # Default keyword if none provided
  # For now, we can ask user or just default to something like "Japan" or "Technology"
  # But the requirement implies searching for a "specific word".
  # I'll default to "Toyota" for demonstration if run without args, or handle it gracefully.
  message("No keyword provided. Usage: Rscript search_nikkei.R <keyword>")
  # For testing purposes in this environment, I'll default to "Toyota" if run interactively,
  # but let's exit if it's meant to be a script.
  # However, for the user's convenience:
  keyword <- "Toyota"
  message("Defaulting to keyword: ", keyword)
}

results <- search_nikkei(keyword)

if (!is.null(results)) {
  print(results)
  write.csv(results, "search_results.csv", row.names = FALSE)
  message("Saved top 10 results to search_results.csv")
}
