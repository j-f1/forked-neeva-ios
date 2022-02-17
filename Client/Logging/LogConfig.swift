// Copyright 2022 Neeva Inc. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Combine
import Defaults
import Foundation
import Shared

public struct LogConfig {
    public enum Interaction: String {
        /// Open neeva menu
        case OpenNeevaMenu
        /// Open tracking shield
        case OpenShield
        /// Open Overflow Menu
        case OpenOverflowMenu
        /// Tap reload page
        case TapReload
        /// Tap stop reload page
        case TapStopReload

        // MARK: bottom nav
        /// Click tab button to see all available tabs
        case ShowTabTray
        /// Click done button to hide the tab tray
        case HideTabTray
        /// Click on any tabs inside the tab tray
        case SelectTab
        /// Click bookmark button to add to space
        case ClickAddToSpaceButton
        /// Click the share button
        case ClickShareButton
        /// Click turn on incognito mode button
        case TurnOnIncognitoMode
        /// Click turn off incognito mode button
        case TurnOffIncognitoMode
        /// Click back button to navigate to previous page
        case ClickBack
        /// Click forward button to navigate to next page
        case ClickForward
        /// Tap and Hold forward button to show navigation stack
        case LongPressForward

        // MARK: tracking shield
        /// Turn on block tracking from shield
        case TurnOnBlockTracking
        /// Turn off block tracking from shield
        case TurnOffBlockTracking
        /// Turn on block tracking from settings
        case TurnOnGlobalBlockTracking
        /// Turn off block tracking from settings
        case TurnOffGlobalBlockTracking

        // MARK: neeva menu
        /// Open home from neeva menu
        case OpenHome
        /// Open spaces from neeva menu
        case OpenSpaces
        /// Open downloads from neeva menu
        case OpenDownloads
        /// Open history from neeva menu
        case OpenHistory
        /// Open settings from neeva menu
        case OpenSetting
        /// Open send feedback from neeva menu
        case OpenSendFeedback

        // MARK: overflow menu
        /// Click the plus new tab button
        case ClickNewTabButton
        /// Click the Find on Page Button
        case ClickFindOnPage
        /// Click the Text Size Button
        case ClickTextSize
        /// Click the Request Desktop Site button
        case ClickRequestDesktop
        /// Click the Download Page Button
        case ClickDownloadPage
        /// Click the Close All Tabs button
        case ClickCloseAllTabs

        // MARK: settings
        /// Click search setting/account setting
        case SettingAccountSettings
        /// Click default browser in setting
        case SettingDefaultBrowser
        /// Click sign out in setting
        case SettingSignout
        /// Click Data Management in setting
        case ViewDataManagement
        /// Click Tracking Protection in setting
        case ViewTrackingProtection
        /// Click Privacy Policy in setting
        case ViewPrivacyPolicy
        /// Click Show Tour in setting
        case ViewShowTour
        /// Click Help Center in setting
        case ViewHelpCenter
        /// Click Licenses in setting
        case ViewLicenses
        /// Click Terms in setting
        case ViewTerms
        /// Click link to navigate to App Settings in System Settings
        case GoToSysAppSettings

        /// Click Clear Private Data in Data Management
        case ClearPrivateData
        /// Click Clear All Website Data in Data Management > Website Data
        case ClearAllWebsiteData

        // MARK: First Run
        /// Click Sign up with Apple on first run
        case FirstRunSignupWithApple
        /// Click Other sign up options on first run
        case FirstRunOtherSignUpOptions
        /// Click sign in on first run
        case FirstRunSignin
        /// Click skip to browser on first run
        case FirstRunSkipToBrowser
        /// First run screen rendered
        case FirstRunImpression
        /// Login after first run
        case LoginAfterFirstRun
        /// Page load at first run and before login
        case FirstRunPageLoad
        /// Sign in from promo card
        case PromoSignin
        /// Sign up on preview promo card
        case PreviewModePromoSignup
        /// Sign in from setting
        case SettingSignin
        /// Error login view triggered by suggestion
        case SuggestionErrorLoginViewImpression
        /// Click Sign in or Join Neeva on suggestion error login page
        case SuggestionErrorSigninOrJoinNeeva
        /// Click Sign in or Join Neeva on space error login page
        case AddToSpaceErrorSigninOrJoinNeeva
        /// Click Sign in or Join Neeva on cheatsheet login page
        case CheatsheetErrorSigninOrJoinNeeva
        /// Open auth panel
        case AuthImpression
        /// Close auth panel
        case AuthClose
        /// Click sign up with Apple on auth panel
        case AuthSignUpWithApple
        /// Click other sign up options on auth panel
        case AuthOtherSignUpOptions
        /// Click sign in on auth panel
        case AuthSignin
        /// Click Sign up with Apple under other options
        case OptionSignupWithApple
        /// Click Sign up with Google under other options
        case OptionSignupWithGoogle
        /// Click Sign up with Microsoft under other options
        case OptionSignupWithMicrosoft
        /// Click Sign up with Apple on auth panel under other options
        case AuthOptionSignupWithApple
        /// Click Sign up with Google on auth panel under other options
        case AuthOptionSignupWithGoogle
        /// Click Sign up with Microsoft on auth panel under other options
        case AuthOptionSignupWithMicrosoft
        /// Click close on the first run under other options
        case OptionClosePanel
        /// Click close on the auth panel under other options
        case AuthOptionClosePanel
        /// Clicked a public space in zero query
        case RecommendedSpaceVisited
        /// Clicked close on preview prompt
        case PreviewPromptClose
        /// Clicked sign up with apple on preview prompt
        case PreviewPromptSignupWithApple
        /// Clicked other signup options on preview prompt
        case PreviewPromptOtherSignupOptions
        /// Clicked sign in on preview prompt
        case PreviewPromptSignIn
        /// Preview home impression
        case PreviewHomeImpression
        /// Clicked on sample query on the home page
        case PreviewSampleQueryClicked
        /// Clicked on the fake search input box on preview home page
        case PreviewTapFakeSearchInput
        /// Click sign in on preview home
        case PreviewHomeSignin
        /// Default browser experiment
        case DefaultBrowserExperimentV2

        // MARK: promo card
        /// Promo card is rendered on screen
        case PromoCardAppear
        /// Click set default browser from promo
        case PromoDefaultBrowser
        /// Close default browser promo card
        case CloseDefaultBrowserPromo
        case DefaultBrowserPromptSkip
        case DefaultBrowserPromptOpen

        // MARK: selected suggestion
        case QuerySuggestion
        case MemorizedSuggestion
        case HistorySuggestion
        case AutocompleteSuggestion
        case PersonalSuggestion
        case BangSuggestion
        case LensSuggestion
        case NoSuggestionQuery
        case NoSuggestionURL
        case FindOnPageSuggestion
        case openSuggestedSearch
        case openSuggestedSite
        case tabSuggestion
        case editCurrentURL

        // MARK: referral promo
        /// Open referral promo
        case OpenReferralPromo
        /// Close referral promo card
        case CloseReferralPromo

        // MARK: performance
        /// App Crash # With Page load #
        case AppCrashWithPageLoad
        /// App Crash # With Crash Reporter
        case AppCrashWithCrashReporter
        /// memory warning with memory footprint
        case LowMemoryWarning
        /// session start = app enter foreground
        case AppEnterForeground

        // MARK: spaces
        case SpacesUIVisited
        case SpacesDetailUIVisited
        case SpacesDetailEntityClicked
        case SpacesDetailEditButtonClicked
        case SpacesDetailShareButtonClicked
        case OwnerSharedSpace
        case FollowerSharedSpace
        case SocialShare
        /// This is for aggregate stats collection
        case space_app_view
        case SaveToSpace
        case BlackFridayPromo
        case CloseBlackFridayPromo
        case BlackFridayNotifyPromo
        case CloseBlackFridayNotifyPromo
        case ViewSpacesFromSheet
        case SpaceFilterClicked
        case OpenSuggestedSpace

        // MARK: ratings card
        case RatingsRateExperience
        case RatingsPromptFeedback
        case RatingsPromptAppStore
        case RatingsLoveit
        case RatingsNeedsWork
        case RatingsDismissedFeedback
        case RatingsDismissedAppReview
        case RatingsSendFeedback
        case RatingsSendAppReview

        // MARK: notification
        case ShowNotificationPrompt
        case NotificationPromptEnable
        case NotificationPromptSkip
        case ShowSystemNotificationPrompt
        case AuthorizeSystemNotification
        case DenySystemNotification
        case ScheduleLocalNotification
        case OpenLocalNotification
        case OpenNotification
        /// When url is opened in default browser
        case OpenDefaultBrowserURL
        /// Click enable notification from promo
        case PromoEnableNotification
        /// Close enable notification promo card
        case CloseEnableNotificationPromo

        // MARK: recipe cheatsheet
        case RecipeCheatsheetImpression
        case RecipeCheatsheetClickBanner
        case RecipeCheatsheetShowMoreRecipe
        case RecipeCheatsheetClickPreferredProvider
        case RecipeCheatsheetUpdatePreferredProvider
        case RelatedRecipeClick
        case RelatedSearchClick

        // MARK: Cheatsheet(NeevaScope)
        case CheatsheetPopoverImpression
        case OpenCheatsheet
        case AckCheatsheetEducationOnSRP
        case AckCheatsheetEducationOnPage
        case CheatsheetEmpty
        case OpenLinkFromCheatsheet

        // MARK: tab group
        case tabGroupClicked
        case tabGroupClosed
        case tabInTabGroupClicked
        case tabRemovedFromGroup

        // MARK: feedback
        case FeedbackFailedToSend

        // MARK: debug mode
        case SignInWithAppleSuccess
        case SignInWithAppleFailed
        case ImplicitDeleteCookie
    }

    /// Specify a comma separated string with these values to
    /// enable specific logging category on the server:
    /// `ios_logging_categories.experiment.yaml`
    public enum InteractionCategory: String, CaseIterable {
        case UI = "UI"
        case NeevaMenu = "NeevaMenu"
        case OverflowMenu = "OverflowMenu"
        case Settings = "Settings"
        case Suggestions = "Suggestions"
        case ReferralPromo = "ReferralPromo"
        case Performance = "Performance"
        case FirstRun = "FirstRun"
        case PromoCard = "PromoCard"
        case Spaces = "Spaces"
        case RatingsCard = "RatingsCard"
        case Notification = "Notification"
        case RecipeCheatsheet = "RecipeCheatsheet"
        case Cheatsheet = "Cheatsheet"
        case TabGroup = "TabGroup"
        case Feedback = "Feedback"
        case DebugMode = "DebugMode"
    }

    public static var enabledLoggingCategories: Set<InteractionCategory>?

    private static var flagsObserver: AnyCancellable?

    public static func featureFlagEnabled(for category: InteractionCategory) -> Bool {
        if category == .FirstRun
            || category == .Notification
            || category == .Suggestions
            || category == .Performance
            || category == .DebugMode
            || category == .PromoCard
        {
            return true
        }

        if enabledLoggingCategories == nil {
            enabledLoggingCategories = Set<InteractionCategory>()
            flagsObserver = Defaults.publisher(NeevaFeatureFlags.stringFlagsKey)
                .combineLatest(
                    Defaults.publisher(NeevaFeatureFlags.stringFlagOverridesKey)
                ).sink { _ in
                    updateLoggingCategory()
                }
            updateLoggingCategory()
        }
        return enabledLoggingCategories?.contains(category) ?? false
    }

    private static func updateLoggingCategory() {
        enabledLoggingCategories?.removeAll()
        NeevaFeatureFlags.latestValue(.loggingCategories)
            .components(separatedBy: ",").forEach { token in
                if let category = InteractionCategory(
                    rawValue: token.stringByTrimmingLeadingCharactersInSet(.whitespaces)
                ) {
                    enabledLoggingCategories?.insert(category)
                }
            }
    }

    public static func category(for interaction: Interaction) -> InteractionCategory {
        switch interaction {
        case .OpenNeevaMenu: return .UI
        case .OpenShield: return .UI
        case .OpenOverflowMenu: return .UI
        case .TapReload: return .UI
        case .TapStopReload: return .UI
        case .ShowTabTray: return .UI
        case .HideTabTray: return .UI
        case .SelectTab: return .UI
        case .ClickAddToSpaceButton: return .UI
        case .ClickShareButton: return .UI
        case .TurnOnIncognitoMode: return .UI
        case .TurnOffIncognitoMode: return .UI
        case .ClickBack: return .UI
        case .ClickForward: return .UI
        case .LongPressForward: return .UI
        case .TurnOnBlockTracking: return .UI
        case .TurnOffBlockTracking: return .UI
        case .TurnOnGlobalBlockTracking: return .UI
        case .TurnOffGlobalBlockTracking: return .UI

        case .OpenHome: return .NeevaMenu
        case .OpenSpaces: return .NeevaMenu
        case .OpenDownloads: return .NeevaMenu
        case .OpenHistory: return .NeevaMenu
        case .OpenSetting: return .NeevaMenu
        case .OpenSendFeedback: return .NeevaMenu

        case .ClickNewTabButton: return .OverflowMenu
        case .ClickFindOnPage: return .OverflowMenu
        case .ClickTextSize: return .OverflowMenu
        case .ClickRequestDesktop: return .OverflowMenu
        case .ClickDownloadPage: return .OverflowMenu
        case .ClickCloseAllTabs: return .OverflowMenu

        case .SettingAccountSettings: return .Settings
        case .SettingDefaultBrowser: return .Settings
        case .SettingSignout: return .Settings
        case .ViewDataManagement: return .Settings
        case .ViewTrackingProtection: return .Settings
        case .ViewPrivacyPolicy: return .Settings
        case .ViewShowTour: return .Settings
        case .ViewHelpCenter: return .Settings
        case .ViewLicenses: return .Settings
        case .ViewTerms: return .Settings
        case .ClearPrivateData: return .Settings
        case .ClearAllWebsiteData: return .Settings

        case .FirstRunSignupWithApple: return .FirstRun
        case .FirstRunOtherSignUpOptions: return .FirstRun
        case .FirstRunSignin: return .FirstRun
        case .FirstRunSkipToBrowser: return .FirstRun
        case .FirstRunImpression: return .FirstRun
        case .LoginAfterFirstRun: return .FirstRun
        case .FirstRunPageLoad: return .FirstRun
        case .PromoSignin: return .FirstRun
        case .PreviewModePromoSignup: return .FirstRun
        case .SettingSignin: return .FirstRun
        case .SuggestionErrorLoginViewImpression: return .FirstRun
        case .SuggestionErrorSigninOrJoinNeeva: return .FirstRun
        case .AddToSpaceErrorSigninOrJoinNeeva: return .FirstRun
        case .CheatsheetErrorSigninOrJoinNeeva: return .FirstRun
        case .AuthImpression: return .FirstRun
        case .AuthClose: return .FirstRun
        case .AuthSignUpWithApple: return .FirstRun
        case .AuthOtherSignUpOptions: return .FirstRun
        case .AuthSignin: return .FirstRun
        case .OptionSignupWithApple: return .FirstRun
        case .OptionSignupWithGoogle: return .FirstRun
        case .OptionSignupWithMicrosoft: return .FirstRun
        case .AuthOptionSignupWithApple: return .FirstRun
        case .AuthOptionSignupWithGoogle: return .FirstRun
        case .AuthOptionSignupWithMicrosoft: return .FirstRun
        case .OptionClosePanel: return .FirstRun
        case .AuthOptionClosePanel: return .FirstRun
        case .RecommendedSpaceVisited: return .FirstRun
        case .PreviewPromptClose: return .FirstRun
        case .PreviewPromptSignupWithApple: return .FirstRun
        case .PreviewPromptOtherSignupOptions: return .FirstRun
        case .PreviewPromptSignIn: return .FirstRun
        case .PreviewHomeImpression: return .FirstRun
        case .PreviewSampleQueryClicked: return .FirstRun
        case .PreviewTapFakeSearchInput: return .FirstRun
        case .PreviewHomeSignin: return .FirstRun
        case .DefaultBrowserExperimentV2: return .FirstRun
        case .DefaultBrowserPromptSkip: return .FirstRun
        case .DefaultBrowserPromptOpen: return .FirstRun

        case .PromoCardAppear: return .PromoCard
        case .PromoDefaultBrowser: return .PromoCard
        case .CloseDefaultBrowserPromo: return .PromoCard
        case .GoToSysAppSettings: return .PromoCard

        case .QuerySuggestion: return .Suggestions
        case .MemorizedSuggestion: return .Suggestions
        case .HistorySuggestion: return .Suggestions
        case .AutocompleteSuggestion: return .Suggestions
        case .PersonalSuggestion: return .Suggestions
        case .BangSuggestion: return .Suggestions
        case .NoSuggestionURL: return .Suggestions
        case .NoSuggestionQuery: return .Suggestions
        case .LensSuggestion: return .Suggestions
        case .FindOnPageSuggestion: return .Suggestions
        case .openSuggestedSearch: return .Suggestions
        case .openSuggestedSite: return .Suggestions
        case .tabSuggestion: return .Suggestions
        case .editCurrentURL: return .Suggestions

        case .OpenReferralPromo: return .ReferralPromo
        case .CloseReferralPromo: return .ReferralPromo

        case .AppCrashWithPageLoad: return .Performance
        case .AppCrashWithCrashReporter: return .Performance
        case .LowMemoryWarning: return .Performance
        case .AppEnterForeground: return .Performance

        case .SpacesUIVisited: return .Spaces
        case .SpacesDetailUIVisited: return .Spaces
        case .SpacesDetailEntityClicked: return .Spaces
        case .SpacesDetailEditButtonClicked: return .Spaces
        case .SpacesDetailShareButtonClicked: return .Spaces
        case .OwnerSharedSpace: return .Spaces
        case .FollowerSharedSpace: return .Spaces
        case .SocialShare: return .Spaces
        case .space_app_view: return .Spaces
        case .SaveToSpace: return .Spaces
        case .BlackFridayPromo: return .Spaces
        case .CloseBlackFridayPromo: return .Spaces
        case .BlackFridayNotifyPromo: return .Spaces
        case .CloseBlackFridayNotifyPromo: return .Spaces
        case .ViewSpacesFromSheet: return .Spaces
        case .SpaceFilterClicked: return .Spaces
        case .OpenSuggestedSpace: return .Spaces

        case .RatingsRateExperience: return .RatingsCard
        case .RatingsPromptFeedback: return .RatingsCard
        case .RatingsPromptAppStore: return .RatingsCard
        case .RatingsLoveit: return .RatingsCard
        case .RatingsNeedsWork: return .RatingsCard
        case .RatingsDismissedFeedback: return .RatingsCard
        case .RatingsDismissedAppReview: return .RatingsCard
        case .RatingsSendFeedback: return .RatingsCard
        case .RatingsSendAppReview: return .RatingsCard

        case .ShowNotificationPrompt: return .Notification
        case .NotificationPromptEnable: return .Notification
        case .NotificationPromptSkip: return .Notification
        case .ShowSystemNotificationPrompt: return .Notification
        case .AuthorizeSystemNotification: return .Notification
        case .DenySystemNotification: return .Notification
        case .ScheduleLocalNotification: return .Notification
        case .OpenLocalNotification: return .Notification
        case .OpenNotification: return .Notification
        case .OpenDefaultBrowserURL: return .Notification
        case .PromoEnableNotification: return .Notification
        case .CloseEnableNotificationPromo: return .Notification

        case .RecipeCheatsheetImpression: return .RecipeCheatsheet
        case .RecipeCheatsheetClickBanner: return .RecipeCheatsheet
        case .RecipeCheatsheetShowMoreRecipe: return .RecipeCheatsheet
        case .RecipeCheatsheetClickPreferredProvider: return .RecipeCheatsheet
        case .RecipeCheatsheetUpdatePreferredProvider: return .RecipeCheatsheet
        case .RelatedRecipeClick: return .RecipeCheatsheet
        case .RelatedSearchClick: return .RecipeCheatsheet

        case .CheatsheetPopoverImpression: return .Cheatsheet
        case .OpenCheatsheet: return .Cheatsheet
        case .AckCheatsheetEducationOnSRP: return .Cheatsheet
        case .AckCheatsheetEducationOnPage: return .Cheatsheet
        case .CheatsheetEmpty: return .Cheatsheet
        case .OpenLinkFromCheatsheet: return .Cheatsheet

        case .tabGroupClicked: return .TabGroup
        case .tabGroupClosed: return .TabGroup
        case .tabInTabGroupClicked: return .TabGroup
        case .tabRemovedFromGroup: return .TabGroup

        case .FeedbackFailedToSend: return .Feedback

        case .SignInWithAppleSuccess: return .DebugMode
        case .SignInWithAppleFailed: return .DebugMode
        case .ImplicitDeleteCookie: return .DebugMode
        }
    }

    public struct Attribute {
        /// Is selected tab in private mode
        public static let IsInPrivateMode = "IsInPrivateMode"
        /// Number of normal tabs opened
        public static let NormalTabsOpened = "NormalTabsOpened"
        /// Number of incognito tabs opened
        public static let PrivateTabsOpened = "PrivateTabsOpened"
        /// User theme setting, i.e dark, light
        public static let UserInterfaceStyle = "UserInterfaceStyle"
        /// Device orientation, i.e. portrait, landscape
        public static let DeviceOrientation = "DeviceOrientation"
        /// Device screen size width x height
        public static let DeviceScreenSize = "DeviceScreenSize"
        /// Is user signed in
        public static let isUserSignedIn = "IsUserSignedIn"
        /// Device name
        public static let DeviceName = "DeviceName"
        /// Session UUID
        public static let SessionUUID = "SessionUUID"
        /// First run search path and query
        public static let FirstRunSearchPathQuery = "FirstRunSearchPathQuery"
        /// First run path, option user clicked on first run screen
        public static let FirstRunPath = "FirstRunPath"
        /// First session uuid when user open the app
        public static let FirstSessionUUID = "FirstSessionUUID"
        /// Preview mode query count
        public static let PreviewModeQueryCount = "PreviewModeQueryCount"
    }

    public struct UIInteractionAttribute {
        /// View from which an UI Interaction is triggered
        public static let fromActionType = "fromActionType"
        public static let openSysSettingSourceView = "openSysSettingSourceView"
        public static let openSysSettingTriggerFrom = "openSysSettingTriggerFrom"
    }

    public struct SuggestionAttribute {
        /// suggestion position
        public static let suggestionPosition = "suggestionPosition"
        /// number of characters typed in url bar
        public static let urlBarNumOfCharsTyped = "urlBarNumOfCharsTyped"
        /// suggestion impression position index
        public static let suggestionTypePosition = "SuggestionTypeAtPosition"
        /// annotation type at position
        public static let annotationTypeAtPosition = "AnnotationTypeAtPosition"
        public static let numberOfMemorizedSuggestions = "NumberOfMemorizedSuggestions"
        public static let numberOfHistorySuggestions = "NumberOfHistorySuggestions"
        public static let numberOfPersonalSuggestions = "NumberOfPersonalSuggestions"
        public static let numberOfCalculatorAnnotations = "NumberOfCalculatorAnnotations"
        public static let numberOfWikiAnnotations = "NumberOfWikiAnnotations"
        public static let numberOfStockAnnotations = "NumberOfStockAnnotations"
        public static let numberOfDictionaryAnnotations = "NumberOfDictionaryAnnotations"
        // query info
        public static let queryInputForSelectedSuggestion = "QueryInputForSelectedSuggestion"
        public static let querySuggestionPosition = "QuerySuggestionPosition"
        public static let selectedMemorizedURLSuggestion = "selectedMemorizedURLSuggestion"
        public static let selectedQuerySuggestion = "SelectedQuerySuggestion"
        // autocomplete
        public static let autocompleteSelectedFromRow = "AutocompleteSelectedFromRow"
        // searchHistory
        public static let fromSearchHistory = "FromSearchHistory"
        // latency
        public static let numberOfCanceledRequest = "NumberOfCanceledRequest"
        public static let timeToFirstScreen = "TimeToFirstScreen"
        public static let timeToSelectSuggestion = "TimeToSelectSuggestion"
    }

    public struct SpacesAttribute {
        public static let spaceID = "space_id"
        public static let spaceEntityID = "SpaceEntityID"
        public static let isShared = "isShared"
        public static let isPublic = "isPublic"
        public static let numberOfSpaceEntities = "NumberOfSpaceEntities"
        public static let socialShareApp = "ShareAppName"
    }

    public struct PromoCardAttribute {
        public static let promoCardType = "promoCardType"
        public static let defaultBrowserPromptExperimentArm = "defaultBrowserPromptExperimentArm"
    }

    public struct CheatsheetAttribute {
        public static let currentCheatsheetQuery = "currentCheatsheetQuery"
        public static let currentPageURL = "currentCheatsheetPageURL"
    }

    public struct TabsAttribute {
        public static let selectedTabIndex = "SelectedTabIndex"
    }

    public struct NotificationAttribute {
        public static let notificationPromptCallSite = "NotificationPromptCallSite"
        public static let notificationAuthorizationCallSite = "notificationAuthorizationCallSite"

        public static let localNotificationTapAction = "LocalNotificationTapAction"
        public static let localNotificationScheduleCallSite = "localNotificationScheduledCallSite"
        public static let localNotificationPromoId = "localNotificationPromoId"
        public static let notificationCampaignId = "NotificationCampaignId"
    }

    public struct PerformanceAttribute {
        public static let memoryUsage = "MemoryUsage"
    }

    public struct TabGroupAttribute {
        public static let numTabsRemoved = "NumTabsRemoved"
        public static let numTabGroupsTotal = "NumTabGroupsTotal"
        public static let numTabsInTabGroup = "NumTabsInTabGroup"
    }

    public struct DeeplinkAttribute {
        public static let searchRedirect = "SearchRedirect"
    }

    public struct TrackingProtectionAttribute {
        public static let toggleProtectionForURL = "ToggleProtectionForURL"
    }
}
