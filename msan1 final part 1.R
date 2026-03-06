# =============================================================================
# Creating a Strategus Analysis Specification: msan1 Part 1
# =============================================================================
#
# Study question:
#   Among patients with testicular germ cell cancer treated with etoposide,
#   what is the relative risk of an acute allergic reaction to etoposide in 
#   those who have received at least one Covid‑19 vaccination prior to etoposide 
#   initiation compared with those who have not received any Covid‑19 vaccination?

# Install and load
install.packages(c("DatabaseConnector", "SqlRender", "dplyr"))
install.packages("remotes")
install.packages("Eunomia")
remotes::install_github("OHDSI/ROhdsiWebApi")
remotes::install_github("OHDSI/CohortGenerator")
remotes::install_github("OHDSI/CohortDiagnostics")
remotes::install_github("OHDSI/Strategus")
remotes::install_github("OHDSI/CohortIncidence")
remotes::install_github("OHDSI/Characterization")
library(DatabaseConnector)
library(CohortGenerator)
library(CohortDiagnostics)
library(SqlRender)
library(dplyr)
library(ROhdsiWebApi)
library(Strategus)
library(CohortIncidence)
library(Characterization)
library(Eunomia)

dir.create("inst/settings", recursive = TRUE, showWarnings = FALSE)

# Connect to ATLAS and test connection
baseUrl <- "https://atlas-demo.ohdsi.org/WebAPI"
# List available data sources on this WebAPI
ROhdsiWebApi::getWebApiVersion(baseUrl = baseUrl)

#Generate cohorts
cohortDefinitionSet <- ROhdsiWebApi::exportCohortDefinitionSet(
  baseUrl       = baseUrl,
  cohortIds     = c(
    1796434, # Germ Cell Tumor treated with Etoposide + Covid Vaccine exposure
    1796435,  # Germ cell tumor treated with Etoposide + NO Covid vaccine exposure
    1796456 # Etoposide allergy (Outcome cohort)
  ),
  generateStats = TRUE
)

cohortDefinitionSet[, c("cohortId", "cohortName")]

# Connect to Eunomia (there will be 0 patients pulled for these cohorts)
connectionDetails <- getEunomiaConnectionDetails()
connection <- connect(connectionDetails)
getTableNames(connection, databaseSchema = "main")

# CohortGenerator creates the required cohort tables
cohortTableNames <- getCohortTableNames(cohortTable = "my_cohort")

createCohortTables(
  connectionDetails = connectionDetails,
  cohortDatabaseSchema = "main",
  cohortTableNames = cohortTableNames
)

# Generate (instantiate) cohorts
cohortsGenerated <- generateCohortSet(
  connectionDetails = connectionDetails,
  cdmDatabaseSchema = "main",
  cohortDatabaseSchema = "main",
  cohortTableNames = cohortTableNames,
  cohortDefinitionSet = cohortDefinitionSet
)

# Verify cohort counts
getCohortCounts(
  connectionDetails = connectionDetails,
  cohortDatabaseSchema = "main",
  cohortTable = "my_cohort"
)

# Peek at the actual cohort table
querySql(connection, "
  SELECT
    cohort_definition_id,
    COUNT(*) AS n_entries,
    COUNT(DISTINCT subject_id) AS n_subjects,
    MIN(cohort_start_date) AS earliest_start,
    MAX(cohort_start_date) AS latest_start
  FROM main.my_cohort
  GROUP BY cohort_definition_id
")

# CohortDiagnostics
cgModule <- CohortGeneratorModule$new()

cohortDefinitionSharedResource <- cgModule$createCohortSharedResourceSpecifications(
  cohortDefinitionSet = cohortDefinitionSet
)

cohortGeneratorModuleSpecifications <- cgModule$createModuleSpecifications(
  generateStats = TRUE                    # default: TRUE
)

# Model specifications
cdModule <- CohortDiagnosticsModule$new()

cohortDiagnosticsModuleSpecifications <- cdModule$createModuleSpecifications(
  cohortIds = NULL,                           # default: NULL (all cohorts)
  runInclusionStatistics = TRUE,              # default: TRUE
  runIncludedSourceConcepts = TRUE,           # default: TRUE
  runOrphanConcepts = TRUE,                   # default: TRUE
  runTimeSeries = FALSE,                      # default: FALSE
  runVisitContext = TRUE,                     # default: TRUE
  runBreakdownIndexEvents = TRUE,             # default: TRUE
  runIncidenceRate = TRUE,                    # default: TRUE
  runCohortRelationship = TRUE,               # default: TRUE
  runTemporalCohortCharacterization = TRUE,   # default: TRUE
  minCharacterizationMean = 0.01,             # default: 0.01
  irWashoutPeriod = 0                         # default: 0
  # temporalCovariateSettings = <module default covariate settings>
)

# CohortIncidence
ciModule <- CohortIncidenceModule$new()

targets <- list(
  CohortIncidence::createCohortRef(id = 1796434, name = "vaccine"),
  CohortIncidence::createCohortRef(id = 1796435, name = "no vaccine")
)

outcomes <- list(
  CohortIncidence::createOutcomeDef(
    id = 1,
    name = "allergy",
    cohortId = 1796456,          # default: 0 (must override)
    cleanWindow = 9999     # default: 0 (we set 9999 = one event per person)
  )
)

tars <- list(
  CohortIncidence::createTimeAtRiskDef(
    id = 1796434,
    startWith = "start",   # default: "start"
    endWith = "end"        # default: "end"
  ),
  CohortIncidence::createTimeAtRiskDef(
    id = 1796435,
    startWith = "start",   # default: "start"
    endWith = "start",     # override: anchor end to start
    endOffset = 365        # default: 0 (we set 365 for fixed 1-year window)
  )
)

incidenceAnalysis <- CohortIncidence::createIncidenceAnalysis(
  targets = c(1, 2),
  outcomes = c(1),
  tars = c(1, 2)
)

irDesign <- CohortIncidence::createIncidenceDesign(
  targetDefs = targets,
  outcomeDefs = outcomes,
  tars = tars,
  analysisList = list(incidenceAnalysis),
  strataSettings = CohortIncidence::createStrataSettings(
    byYear = TRUE,         # default: FALSE
    byGender = TRUE        # default: FALSE
  )
)

cohortIncidenceModuleSpecifications <- ciModule$createModuleSpecifications(
  irDesign = irDesign$toList()
)

# Characterization
cModule <- CharacterizationModule$new()

characterizationModuleSpecifications <- cModule$createModuleSpecifications(
  targetIds = c(1, 2),
  outcomeIds = 3,
  outcomeWashoutDays = c(365),                # default: c(365)
  minPriorObservation = 365,                  # default: 365
  dechallengeStopInterval = 30,               # default: 30
  dechallengeEvaluationWindow = 30,           # default: 30
  riskWindowStart = c(1, 1),                  # default: c(1, 1)
  startAnchor = c("cohort start",             # default: c("cohort start",
                  "cohort start"),             #            "cohort start")
  riskWindowEnd = c(0, 365),                  # default: c(0, 365)
  endAnchor = c("cohort end",                 # default: c("cohort end",
                "cohort end"),                 #            "cohort end")
  minCharacterizationMean = 0.01,             # default: 0.01
  casePreTargetDuration = 365,                # default: 365
  casePostOutcomeDuration = 365,              # default: 365
  includeTimeToEvent = TRUE,                  # default: TRUE
  includeDechallengeRechallenge = TRUE,       # default: TRUE
  includeAggregateCovariate = TRUE            # default: TRUE
  # covariateSettings     = <broad default: demographics, conditions, drugs,
  #                          procedures, measurements at -365d and -30d windows>
  # caseCovariateSettings = <during-exposure covariates: conditions, drugs,
  #                          procedures, devices, measurements, observations>
)

# Create JSON

analysisSpecifications <- createEmptyAnalysisSpecifications() |>
  addSharedResources(cohortDefinitionSharedResource) |>
  addModuleSpecifications(cohortGeneratorModuleSpecifications) |>
  addModuleSpecifications(cohortDiagnosticsModuleSpecifications) |>
  addModuleSpecifications(cohortIncidenceModuleSpecifications) |>
  addModuleSpecifications(characterizationModuleSpecifications)

ParallelLogger::saveSettingsToJson(
  object = analysisSpecifications,
  fileName = "inst/settings/EtoposideAnalysisSpecifications.json"
)

message("Analysis specification saved to: inst/settings/EtoposideAnalysisSpecifications.json")