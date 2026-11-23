# Spec Delta

## Purpose

为主程序提供可持久化的英文和简体中文界面，并允许用户跟随 macOS 语言或明确选择界面语言，同时保持技术标识和用户数据原样显示。

## ADDED Requirements

### Requirement: Language preference controls the main app locale
The main app SHALL offer three language choices: Follow System, Simplified Chinese, and English. The initial value for users without a saved preference SHALL be Follow System.

#### Scenario: First launch uses the system preference
- **WHEN** a user opens MacMonitor without a saved language preference
- **THEN** the language choice is Follow System

#### Scenario: User selects an explicit language
- **WHEN** the user selects Simplified Chinese or English in Settings
- **THEN** all main app user-visible text uses the selected language

### Requirement: System language resolution is deterministic
When Follow System is selected, the app SHALL use Simplified Chinese when the preferred system language is Simplified Chinese or Traditional Chinese, SHALL use English when it is English, and SHALL fall back to English for any other unsupported language.

#### Scenario: Chinese system language
- **WHEN** Follow System is selected and the preferred system language is Chinese
- **THEN** the app displays Simplified Chinese

#### Scenario: English system language
- **WHEN** Follow System is selected and the preferred system language is English
- **THEN** the app displays English

#### Scenario: Unsupported system language
- **WHEN** Follow System is selected and the preferred system language is neither Chinese nor English
- **THEN** the app displays English

### Requirement: Language preference persists
The app SHALL retain the selected language choice across launches until the user changes it.

#### Scenario: Relaunch with an explicit language
- **WHEN** the user selects English, quits the app, and launches it again
- **THEN** the app starts in English without requiring the user to select it again

#### Scenario: Relaunch in Follow System mode
- **WHEN** the user selects Follow System and relaunches the app
- **THEN** the app resolves the language from the current preferred system language

### Requirement: Language changes apply immediately
After the user changes the language choice, all currently open main app surfaces SHALL update without relaunching the app.

#### Scenario: Dashboard is open during a language change
- **WHEN** the Dashboard is open and the user changes from English to Simplified Chinese
- **THEN** Dashboard labels, status text, actions, and readings that contain localized text update immediately

#### Scenario: Multiple main app surfaces are open
- **WHEN** the Dashboard, Settings, or first-run guide is open during a language change
- **THEN** every open surface updates to the selected language without being closed and reopened

#### Scenario: AppKit surfaces are presented after a language change
- **WHEN** the user changes language and then opens a context menu, window title, tooltip, or system alert
- **THEN** that AppKit surface uses the selected language

### Requirement: All main app user-visible text is bilingual
The Dashboard, Settings, first-run guide, context menu, menu bar tooltips, window titles, update states, and system alerts SHALL have an English and a Simplified Chinese user-visible form.

#### Scenario: Simplified Chinese interface
- **WHEN** Simplified Chinese is active
- **THEN** no English descriptive UI text remains except approved technical abbreviations, units, and unchanged source data

#### Scenario: English interface
- **WHEN** English is active
- **THEN** every localized surface continues to display its complete English text

### Requirement: Approved technical data remains unchanged
Localization SHALL preserve CPU, GPU, ANE, DRAM, MHz, GB/s, W, °C, RPM, mAh, MB, GB, percentages, chip model names, process names, and application names in their original form.

#### Scenario: Chinese dashboard contains technical readings
- **WHEN** Simplified Chinese is active
- **THEN** technical abbreviations, units, chip model, and process names remain unchanged while surrounding descriptive labels are localized

### Requirement: Localization does not alter monitoring behavior
Changing or resolving the UI language SHALL NOT change metric values, status thresholds, status colors, menu bar metric selection, or monitoring behavior.

#### Scenario: Thermal status remains semantically consistent
- **WHEN** the UI language changes while the thermal state is unchanged
- **THEN** the displayed thermal status translates to the selected language and retains the same status color and severity

#### Scenario: Menu bar metric layout survives a language change
- **WHEN** the UI language changes and the user has customized visible menu bar metrics
- **THEN** the same metrics remain visible in the same order
