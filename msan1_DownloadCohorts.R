library(dplyr)

# Connect to ATLAS
baseUrl <- "https://atlas-demo.ohdsi.org/WebAPI"
# List available data sources on this WebAPI
ROhdsiWebApi::getWebApiVersion(baseUrl = baseUrl)

#Generate cohorts
cohortDefinitionSet <- ROhdsiWebApi::exportCohortDefinitionSet(
  baseUrl       = baseUrl,
  cohortIds     = c(
    1796434, # Germ Cell Tumor and Covid vaccine exposure
    1796435,  # Germ cell tumor and no Covid vaccine exposure"
    1796456 # Etoposide allergy (Outcome cohort)
  ),
  generateStats = TRUE
)

# Rename cohorts
cohortDefinitionSet[cohortDefinitionSet$cohortId == 1796434,]$cohortName <- "Germ cell tumor and Covid vaccine exposure"
cohortDefinitionSet[cohortDefinitionSet$cohortId == 1796435,]$cohortName <- "Germ cell tumor and no Covid vaccine exposure"
cohortDefinitionSet[cohortDefinitionSet$cohortId == 1796456,]$cohortName <- "Etoposide allergy"

# Re-number cohorts
cohortDefinitionSet[cohortDefinitionSet$cohortId == 1778211,]$cohortId <- 1
cohortDefinitionSet[cohortDefinitionSet$cohortId == 1790989,]$cohortId <- 2
cohortDefinitionSet[cohortDefinitionSet$cohortId == 1780946,]$cohortId <- 3

# Save the cohort definition set
# NOTE: Update settingsFileName, jsonFolder and sqlFolder
# for your study.
CohortGenerator::saveCohortDefinitionSet(
  cohortDefinitionSet = cohortDefinitionSet,
  settingsFileName = "inst/sampleStudy/Cohorts.csv",
  jsonFolder = "inst/sampleStudy/cohorts",
  sqlFolder = "inst/sampleStudy/sql/sql_server",
)
