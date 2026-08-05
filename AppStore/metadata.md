# PocketKernel App Store submission draft

## Name
PocketKernel

## Subtitle
Private AI automations

## Promotional text
Tell PocketKernel what you want done. Review the plan, approve the action, and save repeatable work as an automation — with planning powered privately on your iPhone.

## Description
PocketKernel turns everyday requests into clear, controllable automations.

Just describe what you want:
- Summarize the emails that need attention
- Prepare and send a team update
- Add an approved event to your calendar
- Capture a note in Notion
- Create reminders and focus blocks
- Save repeatable connected-app actions on a schedule

PRIVATE BY DESIGN
Planning runs with Apple’s on-device intelligence. PocketKernel does not send your conversation to a third-party cloud language model.

YOU STAY IN CONTROL
Important actions appear as a clear approval card before they run. You can see recipients, content, dates, destinations, and other relevant details before anything is sent, posted, added, or scheduled.

CONNECT THE APPS YOU USE
Connect supported services on their official sign-in pages. PocketKernel never asks for your service passwords, and you can disconnect at any time.

AUTOMATE REPEAT WORK
Save fixed, approved workflows to run later. Pause, resume, run, or delete automations from one place.

PocketKernel requires a compatible iPhone with Apple Intelligence enabled. Connected-app actions require internet access and the relevant service connection.

## Keywords
AI automation,workflow,assistant,productivity,email,calendar,reminders,Slack,Notion

## Category
Primary: Productivity
Secondary: Utilities

## Review notes
PocketKernel uses Apple Foundation Models on-device for conversational planning and registered tool selection. No third-party cloud LLM is used.

The app creates an anonymous device-scoped PocketKernel identity automatically; no primary-account login is required. Reviewers can use local reminder, calendar, clipboard, URL, notification, and note actions without connecting a third-party account. Significant actions display an approval card before execution.

Third-party service connections use the service’s official authorization page. Provide production OAuth credentials and a review-ready account for any connected-service features shown as available in the submitted build. Unconfigured providers must remain labeled “Coming soon” and cannot be tapped.

Account/data deletion is available at You → Delete my PocketKernel data. Privacy, terms, and support links are available in the same screen.

## Privacy label working draft
Data linked to the user and used for App Functionality:
- Device ID: app-generated device identifier used for an isolated service account
- Other User Content: saved automation titles, prompts, schedules, and fixed action details

Depending on the final enabled service set, review whether Emails or Text Messages must also be declared. PocketKernel does not use data for tracking or advertising.

## Accessibility validation checklist
- VoiceOver labels for icon-only controls
- Dynamic Type through semantic SwiftUI text styles
- Sufficient contrast in light and dark appearance
- No color-only status communication
- 44-point minimum interactive targets
- Reduce Motion does not block core navigation
- Larger Text test on onboarding, approval cards, and automation cards

## Screenshot sequence
1. Home: “Automate anything in plain English”
2. Approval card: “Nothing runs until you approve”
3. Connections: “Connect the apps you already use”
4. Automations: “Put repeat work on autopilot”
5. Privacy: “Planning stays on your iPhone”
