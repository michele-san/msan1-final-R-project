
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


# =============================================================================
# STEP 3: Compose and Save the Analysis Specification JSON
# =============================================================================
#
# Composition order:
#   1. Start with an empty specification
#   2. Add shared resources (cohort definitions)
#   3. Add each module specification
#   4. Save to JSON with ParallelLogger
#
# The resulting JSON is the primary design artifact -- it can be:
#   - Version-controlled and diffed
#   - Reviewed without database access
#   - Executed later at any OMOP CDM site
# -----------------------------------------------------------------------------

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