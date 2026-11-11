%{
  configs: [
    %{
      name: "default",
      plugins: [{ExSlop, []}],
      files: %{
        included: ["lib/", "src/", "test/", "config/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      checks: %{
        extra: [
          {OptimumCredo.Check.Readability.AssignOrder, []},
          {OptimumCredo.Check.Readability.AssignThree, []},
          {OptimumCredo.Check.Readability.BannedAbbreviations, []},
          {OptimumCredo.Check.Readability.BooleanFunctionName, []},
          {OptimumCredo.Check.Readability.CastListOrder, []},
          {OptimumCredo.Check.Readability.DefaultCallbackDefined, []},
          {OptimumCredo.Check.Readability.DepsOrder, []},
          {OptimumCredo.Check.Readability.DescribeFunctionArity,
           [
             # These integration tests group scenarios by user-facing behavior, not one function.
             files: %{
               excluded: [
                 "test/taina/isolation_sweep_test.exs",
                 "test/taina/jaci_test.exs",
                 "test/taina/maraca_test.exs",
                 "test/taina/mural_test.exs",
                 "test/taina/nhaman/backup_test.exs",
                 "test/taina/ybira/rendition_test.exs",
                 "test/taina/ybira_stats_test.exs",
                 "test/taina/ybira_test.exs",
                 "test/taina_web/api/etag_test.exs",
                 "test/taina_web/api/fatia1_test.exs",
                 "test/taina_web/api/fatia_us_test.exs",
                 "test/taina_web/api/invites_test.exs",
                 "test/taina_web/components/layouts_test.exs",
                 "test/taina_web/controllers/session_controller_test.exs",
                 "test/taina_web/live/file_preview_live_test.exs",
                 "test/taina_web/live/files_live_test.exs",
                 "test/taina_web/live/gallery_live_test.exs",
                 "test/taina_web/router_test.exs"
               ]
             }
           ]},
          {OptimumCredo.Check.Readability.DocumentationFormatting, []},
          {OptimumCredo.Check.Readability.EventNameSnakeCase, []},
          {OptimumCredo.Check.Readability.ExtractableSpecTypes, []},
          {OptimumCredo.Check.Readability.GenericModuleName, []},
          {OptimumCredo.Check.Readability.ImplementationHelperInAssertion, []},
          {OptimumCredo.Check.Readability.ImportOrder, []},
          {OptimumCredo.Check.Readability.LlmScaffoldingComment, []},
          {OptimumCredo.Check.Readability.MaybePrefix, []},
          {OptimumCredo.Check.Readability.ModuleAttributeListOrder, []},
          {OptimumCredo.Check.Readability.ModuleOrganization, []},
          {OptimumCredo.Check.Readability.ModulePathMismatch, []},
          {OptimumCredo.Check.Readability.ModuleSelfPrefix, []},
          {OptimumCredo.Check.Readability.PrivateFunctionSpecs, []},
          {OptimumCredo.Check.Readability.RedundantBooleanComparison, []},
          {OptimumCredo.Check.Readability.RedundantFinalAssignment, []},
          {OptimumCredo.Check.Readability.SchemaFieldOrder, []},
          {OptimumCredo.Check.Readability.SingleElementTupleMessage, []},
          {OptimumCredo.Check.Readability.SpecWithImpl, []},
          {OptimumCredo.Check.Readability.TestNameLowercase,
           [
             # Keep protocol names and intentional Portuguese sentence capitalization in these descriptions.
             files: %{
               excluded: [
                 "test/taina_web/api/etag_test.exs",
                 "test/taina_web/api/fatia1_test.exs",
                 "test/taina_web/live/file_preview_live_test.exs",
                 "test/taina_web/live/files_live_test.exs",
                 "test/taina_web/live/saude_live_test.exs"
               ]
             }
           ]},
          {OptimumCredo.Check.Readability.TestNameRepeatsSubject, []},
          {OptimumCredo.Check.Readability.TestPathMismatch,
           [
             # These files intentionally cover workflows, contexts, workers or UI component groups.
             files: %{
               excluded: [
                 "test/taina/isolation_sweep_test.exs",
                 "test/taina/maraca_device_token_test.exs",
                 "test/taina/maraca_members_test.exs",
                 "test/taina/mural_test.exs",
                 "test/taina/ybira/blob_gc_test.exs",
                 "test/taina/ybira/purge_trash_test.exs",
                 "test/taina/ybira/rendition_test.exs",
                 "test/taina/ybira_manifest_test.exs",
                 "test/taina/ybira_stats_test.exs",
                 "test/taina/ybira_upload_limit_test.exs",
                 "test/taina/ypy_lexicons_test.exs",
                 "test/taina_web/api/batch_test.exs",
                 "test/taina_web/api/fatia1_test.exs",
                 "test/taina_web/api/fatia_us_test.exs",
                 "test/taina_web/api/grants_test.exs",
                 "test/taina_web/api/invites_test.exs",
                 "test/taina_web/api/manifest_endpoint_test.exs",
                 "test/taina_web/api/password_test.exs",
                 "test/taina_web/components/actions_test.exs",
                 "test/taina_web/components/content_test.exs",
                 "test/taina_web/components/feedback_test.exs",
                 "test/taina_web/components/file_preview_test.exs",
                 "test/taina_web/components/forms_test.exs",
                 "test/taina_web/components/media_test.exs",
                 "test/taina_web/components/navigation_test.exs",
                 "test/taina_web/components/overlays_test.exs",
                 "test/taina_web/controllers/file_thumbnail_test.exs",
                 "test/taina_web/live/invite_deep_link_test.exs",
                 "test/taina_web/live/invite_flow_test.exs",
                 "test/ypy/cbor_cid_interop_test.exs",
                 "test/ypy/lexicon_registry_test.exs",
                 "test/ypy/maraca_policy_test.exs",
                 "test/ypy/persistence/blob_store_disk_test.exs",
                 "test/ypy/persistence/key_store_files_test.exs",
                 "test/ypy/persistence/maraca_test.exs",
                 "test/ypy/persistence/mural_test.exs",
                 "test/ypy/persistence/ybira_test.exs"
               ]
             }
           ]},
          {OptimumCredo.Check.Readability.TypeParenthesesConsistency, []},
          {OptimumCredo.Check.Readability.TypespecOrder, []},
          {OptimumCredo.Check.Readability.UnusedTypes, []},
          {OptimumCredo.Check.Readability.VerboseAssertions, []},
          {OptimumCredo.Check.Refactor.AdjacentClauseOneLiteral, []},
          {OptimumCredo.Check.Refactor.CaseTrueFalse, []},
          {OptimumCredo.Check.Refactor.ConditionalOnParameter, []},
          {OptimumCredo.Check.Refactor.DuplicateHandleEvent,
           [
             files: %{
               excluded: [
                 # These small screen-specific handlers do not justify a shared on_mount abstraction.
                 "lib/taina_web/live/files_live.ex",
                 "lib/taina_web/live/invite_accept_live.ex",
                 "lib/taina_web/live/invite_live.ex",
                 "lib/taina_web/live/members_live.ex",
                 "lib/taina_web/live/reset_password_live.ex",
                 "lib/taina_web/live/trash_live.ex"
               ]
             }
           ]},
          {OptimumCredo.Check.Refactor.LiveViewBareMatch, []},
          {OptimumCredo.Check.Refactor.RepeatedLiteral, []},
          {OptimumCredo.Check.Refactor.SchemaTableNameMismatch,
           [
             allow_context_prefix: true,
             custom_inflections: %{"concessao" => "concessoes"},
             files: %{excluded: ["lib/taina/ybira/blob_gc.ex", "lib/ypy/mural/entry.ex"]}
           ]},
          {OptimumCredo.Check.Refactor.ToggleOnlyHandleEvent, []},
          {OptimumCredo.Check.Refactor.WithElseManyClauses,
           [
             # Each download error maps to a distinct browser response; keep that boundary explicit.
             files: %{excluded: ["lib/taina_web/controllers/file_controller.ex"]}
           ]},
          {OptimumCredo.Check.Warning.AsyncFalseWithoutComment, []},
          {OptimumCredo.Check.Warning.CallerModuleAttributes, []},
          {OptimumCredo.Check.Warning.CommentedOutCode, []},
          {OptimumCredo.Check.Warning.DescribeWithoutErrorCase,
           [
             # These groups cover pure transformations, boolean outcomes or workflows with errors elsewhere.
             files: %{
               excluded: [
                 "test/taina/cli_test.exs",
                 "test/taina/isolation_sweep_test.exs",
                 "test/taina/jaci/timeline_test.exs",
                 "test/taina/jaci_test.exs",
                 "test/taina/maraca_device_token_test.exs",
                 "test/taina/maraca_members_test.exs",
                 "test/taina/mural_test.exs",
                 "test/taina/nhaman/update_test.exs",
                 "test/taina/ybira/media_test.exs",
                 "test/taina/ybira/rendition_test.exs",
                 "test/taina/ybira_stats_test.exs",
                 "test/taina/ybira_test.exs",
                 "test/taina_web/api/etag_test.exs",
                 "test/taina_web/api/fatia1_test.exs",
                 "test/taina_web/api/fatia_us_test.exs",
                 "test/taina_web/api/grants_test.exs",
                 "test/taina_web/auth_test.exs",
                 "test/taina_web/components/layouts_test.exs",
                 "test/taina_web/live/file_preview_live_test.exs",
                 "test/taina_web/live/files_live_test.exs",
                 "test/taina_web/live/gallery_live_test.exs",
                 "test/taina_web/router_test.exs",
                 "test/taina_web/saude_test.exs",
                 "test/ypy/maraca_policy_test.exs"
               ]
             }
           ]},
          {OptimumCredo.Check.Warning.EnvVarWithoutFailure, []},
          {OptimumCredo.Check.Warning.ExplicitIndexName, []},
          {OptimumCredo.Check.Warning.ExternalCallInMigration, []},
          {OptimumCredo.Check.Warning.HardcodedAssetPath, []},
          {OptimumCredo.Check.Warning.HardcodedYearInTest,
           [
             # Fixed timestamps are deterministic fixtures and format boundaries, not today-dependent tests.
             files: %{
               excluded: [
                 "test/taina/jaci/timeline_test.exs",
                 "test/taina/jaci_test.exs",
                 "test/taina/nhaman/backup_test.exs",
                 "test/taina/ybira/media_test.exs",
                 "test/taina/ybira/rendition_test.exs",
                 "test/taina_web/api/etag_test.exs",
                 "test/taina_web/api/serializer_test.exs",
                 "test/taina_web/components/media_test.exs",
                 "test/taina_web/time_test.exs",
                 "test/ypy/lexicon/validate_test.exs",
                 "test/ypy/maraca_policy_test.exs",
                 "test/ypy/persistence/ybira_test.exs",
                 "test/ypy/wire_test.exs"
               ]
             }
           ]},
          {OptimumCredo.Check.Warning.HiddenIdInput, []},
          {OptimumCredo.Check.Warning.HttpClientInTest, []},
          {OptimumCredo.Check.Warning.LoggerErrorWithoutContext, []},
          {OptimumCredo.Check.Warning.MixOutsideBuildConfig, []},
          {OptimumCredo.Check.Warning.NarrowRandomRange, []},
          {OptimumCredo.Check.Warning.NotNullWithoutDefault, []},
          {OptimumCredo.Check.Warning.RawSqlIndexInMigration, []},
          {OptimumCredo.Check.Warning.ReferenceWithoutOnDelete, []},
          {OptimumCredo.Check.Warning.RepoCallInEnumeration, []},
          {OptimumCredo.Check.Warning.RequiredFieldConsistency,
           [
             files: %{
               excluded: [
                 # PublicId is autogenerated; DeviceToken.token_hash is set by the context.
                 "lib/taina/maraca/device_token.ex",
                 "lib/ypy/maraca/ava.ex",
                 "lib/ypy/maraca/concessao.ex",
                 "lib/ypy/maraca/pedido.ex",
                 "lib/ypy/maraca/tekoa.ex"
               ]
             }
           ]},
          {OptimumCredo.Check.Warning.SchemaModuleInMigration, []},
          {OptimumCredo.Check.Warning.SeedInsertWithoutOnConflict, []},
          {OptimumCredo.Check.Warning.SleepInTest, []},
          {OptimumCredo.Check.Warning.SleepOutsideTest, []},
          {OptimumCredo.Check.Warning.StaleRenderBinding,
           [
             # This assertion intentionally compares output before and after an unrelated message.
             files: %{excluded: ["test/taina_web/live/saude_live_test.exs"]}
           ]},
          {OptimumCredo.Check.Warning.UnsafeAtomConversion, []},
          {OptimumCredo.Check.Warning.WebNamespaceInCore, []},
          # ---
          {Jump.CredoChecks.AssertElementSelectorCanNeverFail, []},
          {Jump.CredoChecks.AssertReceiveTimeout, min_assert_receive_timeout: 1_000, max_refute_receive_timeout: 100},
          {Jump.CredoChecks.AvoidFunctionLevelElse, []},
          {Jump.CredoChecks.AvoidLoggerConfigureInTest, []},
          {Jump.CredoChecks.AvoidModifyingStructBeforeChangeset, []},
          {Jump.CredoChecks.AvoidSocketAssignsInTest,
           [
             # These tests directly verify the on_mount assignment contract.
             files: %{excluded: ["test/taina_web/auth_test.exs", "test/taina_web/plugs/"]}
           ]},
          {Jump.CredoChecks.ConditionalAssertion, []},
          {Jump.CredoChecks.DoctestIExExamples,
           [
             derive_test_path: fn filename ->
               filename
               |> String.replace_leading("lib/", "test/")
               |> String.replace_trailing(".ex", "_test.exs")
             end,
             # These examples are host-dependent or illustrative with aliases and seeded database state.
             files: %{
               excluded: [
                 "lib/taina/guara/chat.ex",
                 "lib/taina/guara/message.ex",
                 "lib/taina/guara/participant.ex",
                 "lib/taina/repo.ex",
                 "lib/taina_web/disk.ex"
               ]
             }
           ]},
          {Jump.CredoChecks.LiveViewFormCanBeRehydrated, excluded: ["lib/taina/"]},
          {Jump.CredoChecks.LiveViewPubSubRequiresConnected, []},
          {Jump.CredoChecks.NoManualContentDisposition, [files: %{excluded: ["lib/taina_web/file_serving.ex"]}]},
          {Jump.CredoChecks.NoWordSigilInterpolation, []},
          {Jump.CredoChecks.UndeclaredExternalResource, []},
          {Jump.CredoChecks.PreferChangeOverUpDownMigrations, []},
          {Jump.CredoChecks.PreferTextColumns, start_after: "20240101000000"},
          {Jump.CredoChecks.SafeBinaryToTerm, []},
          {Jump.CredoChecks.TestHasNoAssertions, custom_assertion_functions: [:await_has, :await_with_timeout]},
          {Jump.CredoChecks.TooManyAssertions,
           [
             max_assertions: 20,
             # This single home-screen smoke test intentionally checks the whole shell at the configured limit.
             files: %{excluded: ["test/taina_web/live/home_live_test.exs"]}
           ]},
          {Jump.CredoChecks.TopLevelAliasImportRequire, []},
          {Jump.CredoChecks.UnusedLiveViewAssign,
           [
             # Gallery state is read through the nested @gallery component assigns.
             excluded: ["lib/taina_web/live/gallery_live.ex"],
             ignored_assigns: [:active_path]
           ]},
          {Jump.CredoChecks.VacuousTest,
           [
             ignore_setup_only_tests?: false,
             # Struct construction and @enforce_keys are the public contract under test.
             files: %{excluded: ["test/ypy/scope_test.exs"]},
             library_modules: [
               Ecto,
               Oban,
               Phoenix,
               Plug
             ]
           ]},
          {Jump.CredoChecks.WeakAssertion, []},
          # ---
          {OeditusCredo.Check.Warning.MissingErrorHandling, [exclude_test_files: true]},
          {OeditusCredo.Check.Warning.SilentErrorCase, []},
          {OeditusCredo.Check.Warning.SwallowingException, []},
          # Database & Performance
          {OeditusCredo.Check.Warning.InefficientFilter, []},
          {OeditusCredo.Check.Warning.NPlusOneQuery, []},
          {OeditusCredo.Check.Warning.MissingPreload, []},
          # LiveView & Concurrency
          {OeditusCredo.Check.Warning.SyncOverAsync, []},
          {OeditusCredo.Check.Warning.MissingHandleAsync, []},
          {OeditusCredo.Check.Warning.MissingThrottle, []},
          {OeditusCredo.Check.Warning.InlineJavascript, []},
          # Readability
          {OeditusCredo.Check.Readability.UnnecessaryInterpolatingSigil, []},
          # Code Quality
          {OeditusCredo.Check.Warning.DirectStructUpdate, []},
          {OeditusCredo.Check.Warning.CallbackHell, [max_nesting: 2]},
          {OeditusCredo.Check.Warning.BlockingInPlug, []},
          # Code Organization & Idiomatic Refactoring
          {OeditusCredo.Check.Refactoring.PreferCasePatternMatching, []},
          {OeditusCredo.Check.Refactoring.PreferMultiHeadFunction, []},
          {OeditusCredo.Check.Refactoring.PreferMultiHeadForNil, []},
          {OeditusCredo.Check.Refactoring.PreferPipelineOperator,
           [
             # A one-step pipeline here conflicts with AvoidSinglePipe and obscures scope construction.
             files: %{
               excluded: [
                 "test/taina/ybira/purge_trash_test.exs",
                 "test/taina/ybira_stats_test.exs",
                 "test/taina/ybira_upload_limit_test.exs"
               ]
             }
           ]},
          {OeditusCredo.Check.Refactoring.PreferInplaceMapMatching, []},
          {OeditusCredo.Check.Refactoring.PreferInplaceListMatching, []},
          {OeditusCredo.Check.Refactoring.PreferInplaceBinaryMatching, []},
          {OeditusCredo.Check.Refactoring.PreferDestructuring, []},
          {OeditusCredo.Check.Refactoring.PreferDotAccessForStructs, []},
          {OeditusCredo.Check.Refactoring.PreferWithClause, []},
          {OeditusCredo.Check.Refactoring.PreferTaggedTuplesForErrors, []},
          {OeditusCredo.Check.Refactoring.PreferForComprehensionOverFilterMap, []},
          {OeditusCredo.Check.Refactoring.PreferListPrepend, []},
          {OeditusCredo.Check.Refactoring.PreferPatternMatchingForEmptiness, []},
          {OeditusCredo.Check.Refactoring.PreferStringBoundariesOverRegex, []},
          {OeditusCredo.Check.Refactoring.PreferFunctionCapture, []},
          {OeditusCredo.Check.Refactoring.PreferShortFieldAccessCapture, []},
          {OeditusCredo.Check.Refactoring.PreferMapMerge, []},
          {OeditusCredo.Check.Refactoring.AvoidSinglePipe, []},
          {OeditusCredo.Check.Refactoring.AvoidUnawaitedTaskAsync, []},
          # Refactoring Suggestions
          {OeditusCredo.Check.Refactoring.SuggestFSM, []},
          # Telemetry & Observability
          {OeditusCredo.Check.Warning.TelemetryInRecursiveFunction, []},
          {OeditusCredo.Check.Warning.MissingTelemetryInAuthPlug, []},
          {OeditusCredo.Check.Warning.MissingTelemetryForExternalHttp, []},
          # Security - Injection
          {OeditusCredo.Check.Security.SQLInjection, []},
          {OeditusCredo.Check.Security.OSCommandInjection, []},
          {OeditusCredo.Check.Security.CodeInjection, []},
          {OeditusCredo.Check.Security.XSSVulnerability, []},
          # Security - Auth
          {OeditusCredo.Check.Security.MissingAuthentication,
           [
             files: %{
               excluded: [
                 # Authentication is enforced by the router pipelines, not duplicated in controllers.
                 ~r"lib/taina_web/api/",
                 "lib/taina_web/controllers/health_controller.ex",
                 "lib/taina_web/controllers/password_controller.ex",
                 "lib/taina_web/controllers/session_controller.ex",
                 "lib/taina_web/controllers/setup_controller.ex"
               ]
             }
           ]},
          {OeditusCredo.Check.Security.MissingAuthorization, []},
          {OeditusCredo.Check.Security.IncorrectAuthorization, []},
          {OeditusCredo.Check.Security.InsecureDirectObjectReference, []},
          # Security - Data Protection
          {OeditusCredo.Check.Security.SensitiveDataExposure, []},
          {OeditusCredo.Check.Security.HardcodedCredentials, [files: %{excluded: ["lib/taina_web/components/icons.ex"]}]},
          {OeditusCredo.Check.Security.UnsafeDeserialization, []},
          # Security - Input & File Handling
          {OeditusCredo.Check.Security.ImproperInputValidation, []},
          {OeditusCredo.Check.Security.PathTraversal,
           [
             files: %{
               excluded: [
                 # Storage paths derive from configured roots and validated CID/numeric identifiers.
                 "lib/ypy/blob_store/disk.ex",
                 "lib/ypy/key_store/files.ex",
                 "lib/ypy/lexicon.ex",
                 "lib/taina_web/live/file_preview_live.ex",
                 "lib/taina_web/live/trash_preview_live.ex"
               ]
             }
           ]},
          {OeditusCredo.Check.Security.UnrestrictedFileUpload, []},
          # Security - Web
          {OeditusCredo.Check.Security.MissingCSRFProtection,
           [
             exclude_test_files: true,
             files: %{
               excluded: [
                 # Browser routes use protect_from_forgery; API routes use Bearer tokens, not cookies.
                 "lib/taina_web/router.ex",
                 "lib/taina_web/controllers/session_controller.ex",
                 ~r"lib/taina_web/api/",
                 # Ypy put/delete functions are storage and ledger operations, not HTTP routes.
                 ~r"lib/ypy/"
               ]
             }
           ]},
          {OeditusCredo.Check.Security.SSRFVulnerability, []},
          # Security - Race Conditions
          {OeditusCredo.Check.Security.TOCTOU, []}
        ]
      }
    }
  ]
}
