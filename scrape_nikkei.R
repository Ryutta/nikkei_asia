# Load necessary libraries
# To install: install.packages(c("rvest", "jsonlite", "dplyr"))
library(rvest)
library(jsonlite)
library(dplyr)

# Function to extract news from Nikkei Asia
extract_news <- function() {
  url <- "https://asia.nikkei.com/"

  # Fetch the webpage
  # We use tryCatch to handle potential network errors
  webpage <- tryCatch(read_html(url), error = function(e) {
    message("Failed to fetch URL: ", e$message)
    return(NULL)
  })

  if (is.null(webpage)) return(NULL)

  # Extract the __NEXT_DATA__ script which contains the page data in JSON format
  # This is more robust than scraping HTML classes which may change frequently
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

  # 1. Homepage Latest Headlines (Priority)
  # This usually contains the most recent top news (approx 5 items)
  if (!is.null(props$homepageLatestHeadlines$items)) {
    df <- props$homepageLatestHeadlines$items
    if ("name" %in% names(df) && "path" %in% names(df)) {
      all_articles[[length(all_articles) + 1]] <- df %>% select(title = name, path)
    }
  }

  # 2. Extract from content blocks
  # The page is composed of blocks which may contain lists of articles (e.g. Opinion, specific topics)
  if (!is.null(props$data$blocks)) {
    blocks <- props$data$blocks
    # Iterate through blocks to find articles
    # blocks is a data frame, iterate row by row
    if (nrow(blocks) > 0) {
      for (i in seq_len(nrow(blocks))) {
        # Check 'items' list in the block
        if ("items" %in% names(blocks) && !is.null(blocks$items)) {
           items <- blocks$items[[i]]
           if (!is.null(items) && is.data.frame(items)) {
             # Standard article structure (name, path)
             if ("name" %in% names(items) && "path" %in% names(items)) {
               df <- items %>% select(title = name, path)
               all_articles[[length(all_articles) + 1]] <- df
             }
             # Alternative structure (headline, url)
             else if ("headline" %in% names(items) && "url" %in% names(items)) {
                df <- items %>% select(title = headline, path = url)
                all_articles[[length(all_articles) + 1]] <- df
             }
           }
        }

        # Check for direct headline in the block itself (e.g. single article block)
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

  # 3. Most Read (Fallback/Supplement)
  if (!is.null(props$mostReadArticles)) {
    df <- props$mostReadArticles
    if ("title" %in% names(df) && "path" %in% names(df)) {
      all_articles[[length(all_articles) + 1]] <- df %>% select(title, path)
    }
  }

  # Combine and Process
  if (length(all_articles) > 0) {
    combined <- bind_rows(all_articles)

    # Filter valid entries
    combined <- combined %>% filter(!is.na(title) & !is.na(path) & title != "")

    # Normalize links
    combined$link <- sapply(combined$path, function(p) {
      if (grepl("^http", p)) {
        return(p)
      } else if (grepl("^/", p)) {
        return(paste0("https://asia.nikkei.com", p))
      } else {
        return(paste0("https://asia.nikkei.com/", p))
      }
    })

    # Deduplicate by link (keep the first occurrence which is from higher priority source)
    combined <- combined %>% distinct(link, .keep_all = TRUE)

    # Select title and link
    result <- combined %>% select(title, link)

    # Return top 10
    return(head(result, 10))
  }

  return(NULL)
}

# Run the function
news_list <- extract_news()

# Print and save result
if (!is.null(news_list)) {
  print(news_list)
  # Write to CSV
  write.csv(news_list, "nikkei_news_top10.csv", row.names = FALSE)
  message("Successfully scraped top 10 news articles.")
} else {
  message("No news found.")
}
