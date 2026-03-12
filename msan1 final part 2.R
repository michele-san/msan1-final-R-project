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
remotes::install_github("OHDSI/CohortMethod")

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
library(CohortMethod)

dir.create("inst/settings", recursive = TRUE, showWarnings = FALSE)

# Connect to ATLAS and test connection
baseUrl <- "https://atlas-demo.ohdsi.org/WebAPI"
# List available data sources on this WebAPI
ROhdsiWebApi::getWebApiVersion(baseUrl = baseUrl)

#Generate cohorts
cohortDefinitionSet <- ROhdsiWebApi::exportCohortDefinitionSet(
  baseUrl       = baseUrl,
  cohortIds     = c(
    1796434, #Germ cell tumor and Covid vaccine exposure
    1796435,  # Germ cell tumor and no Covid vaccine exposure"
    1796456 # Etoposide allergy (Outcome cohort)
  ),
  generateStats = TRUE
)

cohortDefinitionSet <- cohortDefinitionSet |>
  mutate(
    cohortName = case_when(
      cohortId == 1796434 ~ "Germ cell tumor and Covid vaccine exposure",
      cohortId == 1796435 ~ "Germ cell tumor and Covid vaccine exposure",
      cohortId == 1796456 ~ "Etoposide allergy",
      TRUE ~ cohortName
    ),
    cohortId = case_when(
      cohortId == 1796434 ~ 1, #target
      cohortId == 1796435 ~ 2, #comparator
      cohortId == 1796456 ~ 3 #outcome
    )
  )

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
  irWashoutPeriod = 365                         # default: 0
  # temporalCovariateSettings = <module default covariate settings>
)

# CohortIncidence
ciModule <- CohortIncidenceModule$new()

targets <- list(
  CohortIncidence::createCohortRef(id = 1, name = "vaccine"),
  CohortIncidence::createCohortRef(id = 2, name = "no vaccine")
)

outcomes <- list(
  CohortIncidence::createOutcomeDef(
    id = 3,
    name = "allergy",
    cohortId = 1796456,          # default: 0 (must override)
    cleanWindow = 9999     # default: 0 (we set 9999 = one event per person)
  )
)

tars <- list(
  CohortIncidence::createTimeAtRiskDef(
    id = 1,
    startWith = "start",   # default: "start"
    endWith = "end"        # default: "end"
  ),
  CohortIncidence::createTimeAtRiskDef(
    id = 2,
    startWith = "start",   # default: "start"
    endWith = "start",     # override: anchor end to start
    endOffset = 365        # default: 0 (we set 365 for fixed 1-year window)
  )
)

incidenceAnalysis <- CohortIncidence::createIncidenceAnalysis(
  targets = c(1, 2),
  outcomes = c(3),
  tars = c(1, 2)
)

irDesign <- CohortIncidence::createIncidenceDesign(
  targetDefs = targets,
  outcomeDefs = outcomes,
  tars = tars,
  analysisList = list(incidenceAnalysis),
  strataSettings = CohortIncidence::createStrataSettings(
    byYear = TRUE,         # default: FALSE
    byGender = FALSE        # default: FALSE
  )
)

cohortIncidenceModuleSpecifications <- ciModule$createModuleSpecifications(
  irDesign = irDesign$toList()
)

# Characterization
cModule <- CharacterizationModule$new()

characterizationModuleSpecifications <- cModule$createModuleSpecifications(
  targetIds = c(1796434, 1796435),
  outcomeIds = 1796456,
  outcomeWashoutDays = c(365),                # default: c(365)
  minPriorObservation = 365,                  # default: 365
  dechallengeStopInterval = 9999,               # default: 30
  dechallengeEvaluationWindow = 9999,           # default: 30
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

# CohortMethod (This is where part 2 assignment starts)

# createModuleSpecifications defaults:
#   cmAnalysisList                  = <required>
#   targetComparatorOutcomesList    = <required>
#   analysesToExclude               = NULL
#   refitPsForEveryOutcome          = FALSE
#   refitPsForEveryStudyPopulation  = TRUE
#   cmDiagnosticThresholds          = CohortMethod::createCmDiagnosticThresholds()
#
# createTargetComparatorOutcomes defaults:
#   excludedCovariateConceptIds = c()
#   includedCovariateConceptIds = c()
#
# createOutcome defaults:
#   outcomeOfInterest   = TRUE
#   trueEffectSize      = NA
#   priorOutcomeLookback = NULL
#   riskWindowStart     = NULL
#   startAnchor         = NULL
#   riskWindowEnd       = NULL
#   endAnchor           = NULL
#
# createCmAnalysis defaults:
#   analysisId                        = 1
#   description                       = ""
#   getDbCohortMethodDataArgs         = <required>
#   createStudyPopArgs                = <required>
#   createPsArgs                      = NULL
#   trimByPsArgs                      = NULL
#   trimByPsToEquipoiseArgs           = NULL
#   trimByIptwArgs                    = NULL
#   truncateIptwArgs                  = NULL
#   matchOnPsArgs                     = NULL
#   matchOnPsAndCovariatesArgs        = NULL
#   stratifyByPsArgs                  = NULL
#   stratifyByPsAndCovariatesArgs     = NULL
#   computeSharedCovariateBalanceArgs = NULL
#   computeCovariateBalanceArgs       = NULL
#   fitOutcomeModelArgs               = NULL
#
# createGetDbCohortMethodDataArgs defaults:
#   studyStartDate       = ""
#   studyEndDate         = ""
#   firstExposureOnly    = FALSE
#   removeDuplicateSubjects = "keep all"
#   restrictToCommonPeriod  = FALSE
#   washoutPeriod        = 0
#   maxCohortSize        = 0
#   covariateSettings    = <required>
#
# createCreateStudyPopulationArgs defaults:
#   firstExposureOnly             = FALSE
#   restrictToCommonPeriod        = FALSE
#   washoutPeriod                 = 0
#   removeDuplicateSubjects       = "keep all"
#   removeSubjectsWithPriorOutcome = TRUE
#   priorOutcomeLookback          = 99999
#   minDaysAtRisk                 = 1
#   maxDaysAtRisk                 = 99999
#   riskWindowStart               = 0
#   startAnchor                   = "cohort start"
#   riskWindowEnd                 = 0
#   endAnchor                     = "cohort end"
#   censorAtNewRiskWindow         = FALSE
#
# createCreatePsArgs defaults:
#   maxCohortSizeForFitting = 250000
#   errorOnHighCorrelation  = TRUE
#   stopOnError             = TRUE
#   prior                   = createPrior("laplace", exclude = c(0), useCrossValidation = TRUE)
#   control                 = createControl(noiseLevel = "silent", cvType = "auto", ...)
#
# createStratifyByPsArgs defaults:
#   numberOfStrata       = 5
#   stratificationColumns = c()
#   baseSelection        = "all"
#
# createFitOutcomeModelArgs defaults:
#   modelType               = "logistic"
#   stratified              = FALSE
#   useCovariates           = FALSE
#   inversePtWeighting      = FALSE
#   interactionCovariateIds = c()
#   excludeCovariateIds     = c()
#   includeCovariateIds     = c()
#   profileGrid             = NULL
#   profileBounds           = c(log(0.1), log(10))
#   prior                   = createPrior("laplace", useCrossValidation = TRUE)
#   control                 = createControl(cvType = "auto", seed = 1, ...)

cmModule <- CohortMethodModule$new()

targetComparatorOutcomesList <- list(
  CohortMethod::createTargetComparatorOutcomes(
    targetId = 1796434,
    comparatorId = 1796435,
    outcomes = list(
      CohortMethod::createOutcome(
        outcomeId = 1796456,
        outcomeOfInterest = TRUE    # default: TRUE
      )
    )
    # excludedCovariateConceptIds = c(),   # default: c()
    # includedCovariateConceptIds = c()    # default: c()
  )
)

cmAnalysisList <- list(
  CohortMethod::createCmAnalysis(
    analysisId = 1,                              # default: 1
    description = "Covid vaccination or no vaccination for etoposide allergy", # default: ""
    getDbCohortMethodDataArgs = CohortMethod::createGetDbCohortMethodDataArgs(
      # studyStartDate = "",                    # default: ""
      # studyEndDate = "",                      # default: ""
      # firstExposureOnly = FALSE,               # default: FALSE
      # removeDuplicateSubjects = "keep all",   # default: "keep all"
      # restrictToCommonPeriod = FALSE,          # default: FALSE
      # washoutPeriod = 0,                       # default: 0
      # maxCohortSize = 0,                       # default: 0
      covariateSettings = FeatureExtraction::createDefaultCovariateSettings()
    ),
    createStudyPopulationArgs = CohortMethod::createCreateStudyPopulationArgs(
      removeSubjectsWithPriorOutcome = TRUE,   # default: TRUE
      riskWindowStart = 1,                     # default: 0 (we set 1 day post-index)
      riskWindowEnd = 0,                       # default: 0
      startAnchor = "cohort start",           # default: "cohort start"
      endAnchor = "cohort end"                # default: "cohort end"
      # firstExposureOnly = FALSE,             # default: FALSE
      # restrictToCommonPeriod = FALSE,        # default: FALSE
      # washoutPeriod = 0,                     # default: 0
      # removeDuplicateSubjects = "keep all", # default: "keep all"
      # priorOutcomeLookback = 99999,          # default: 99999
      # minDaysAtRisk = 1,                     # default: 1
      # maxDaysAtRisk = 99999,                 # default: 99999
      # censorAtNewRiskWindow = FALSE          # default: FALSE
    ),
    createPsArgs = CohortMethod::createCreatePsArgs(
      maxCohortSizeForFitting = 250000,        # default: 250000
      errorOnHighCorrelation = TRUE,           # default: TRUE
      stopOnError = TRUE                       # default: TRUE
    ),
    stratifyByPsArgs = CohortMethod::createStratifyByPsArgs(
      numberOfStrata = 5                      # default: 5
      # stratificationColumns = c(),          # default: c()
      # baseSelection = "all"                # default: "all"
    ),
    fitOutcomeModelArgs = CohortMethod::createFitOutcomeModelArgs(
      modelType = "cox",                     # default: "logistic"
      stratified = TRUE                       # default: FALSE
      # useCovariates = FALSE,                # default: FALSE
      # inversePtWeighting = FALSE,           # default: FALSE
      # interactionCovariateIds = c(),        # default: c()
      # excludeCovariateIds = c(),            # default: c()
      # includeCovariateIds = c()             # default: c()
    )
    # trimByPsArgs = NULL,                    # default: NULL
    # trimByPsToEquipoiseArgs = NULL,         # default: NULL
    # trimByIptwArgs = NULL,                  # default: NULL
    # truncateIptwArgs = NULL,                # default: NULL
    # matchOnPsArgs = NULL,                   # default: NULL
    # matchOnPsAndCovariatesArgs = NULL,      # default: NULL
    # stratifyByPsAndCovariatesArgs = NULL,   # default: NULL
    # computeSharedCovariateBalanceArgs = NULL, # default: NULL
    # computeCovariateBalanceArgs = NULL      # default: NULL
  )
)

cohortMethodModuleSpecifications <- cmModule$createModuleSpecifications(
  cmAnalysisList = cmAnalysisList,
  targetComparatorOutcomesList = targetComparatorOutcomesList
  # analysesToExclude = NULL,                 # default: NULL
  # refitPsForEveryOutcome = FALSE,           # default: FALSE
  # refitPsForEveryStudyPopulation = TRUE,    # default: TRUE
  # cmDiagnosticThresholds = CohortMethod::createCmDiagnosticThresholds()
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
  fileName = "inst/settings/EtoposideAnalysisSpecifications_part2.json"
)

message("Analysis specification saved to: inst/settings/EtoposideAnalysisSpecifications_part2.json")