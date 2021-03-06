//
//  Report.swift
//  
//
//  Created by Connor Ricks on 6/4/20.
//

import Foundation
import Ink

struct Report: Equatable {
    
    // MARK: Constants
    
    private enum Constants {
        static let textReportWidth = 65
        static let textTitlePrefix = "===== "
    }
    
    // MARK: Properties
    
    private let created: Date
    
    private let version: String
    
    private let startBranch: String
    private let endBranch: String
    
    private let commits: [GitCommit]
    private let issues: [JiraIssue]
    
    private let nonMergeCommits: [GitCommit]
    
    private let commitsWithoutIssues: [GitCommit]
    private let commitsWithoutIssuesPercentage: String
    
    private let commitsWithUnwantedIssues: [GitCommit]
    private let commitsWithUnwantedIssuesPercentage: String
    
    private let incompleteIssues: [JiraIssue]
    private let incompleteIssuesPercentage: String
    
    private let issuesWithoutCommits: [JiraIssue]
    private let issuesWithoutCommitsPercentage: String
    
    var createdString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: created)
    }
    
    var reportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let dateString = formatter.string(from: Date())
        return "commit_checker_\(version)_\(projects.joined(separator: "_"))_\(dateString)"
    }
    
    // MARK: Initializers
    
    init(version: String,
         commits: [GitCommit],
         issues: [JiraIssue],
         startBranch: String,
         endBranch: String,
         projects: [String]) {
        
        Messenger.analyze("Generating report for verion \(version)...")
        
        self.created = Date()
        self.version = version
        
        self.startBranch = startBranch
        self.endBranch = endBranch
        
        self.commits = commits
        self.issues = issues
        
        Messenger.analyze("Analyzing \(commits.count) commits and \(issues.count) issues...")
        self.nonMergeCommits = commits.nonMergeCommits
        Messenger.analyze("\(commits.count - nonMergeCommits.count) merge commits.")
        self.commitsWithoutIssues = nonMergeCommits.commitsWithoutIssues
        self.commitsWithoutIssuesPercentage = (Double(commitsWithoutIssues.count) / Double(nonMergeCommits.count)).percent()
        Messenger.warn("\(commitsWithoutIssues.count) commits that don't contain an issue.")
        self.commitsWithUnwantedIssues = Report.commitsWithUnwantedIssues(commits: nonMergeCommits, issues: issues)
        self.commitsWithUnwantedIssuesPercentage = (Double(commitsWithUnwantedIssues.count) / Double(nonMergeCommits.count)).percent()
        Messenger.warn("\(commitsWithUnwantedIssues.count) commits for work not in \(version)")
        self.incompleteIssues = issues.incompleteIssues
        self.incompleteIssuesPercentage = (Double(incompleteIssues.count) / Double(issues.count)).percent()
        Messenger.warn("\(incompleteIssues.count) incomplete issues.")
        self.issuesWithoutCommits = Report.issuesWithoutCommits(commits: nonMergeCommits, issues: issues)
        self.issuesWithoutCommitsPercentage = (Double(issuesWithoutCommits.count) / Double(issues.count)).percent()
        Messenger.warn("\(issuesWithoutCommits.count) issues not referenced in any commit.")
    }
    
    // MARK: Output
    
    func output() {
        let path = Configuration.current.report.output
        switch Configuration.current.report.format {
        case .html:
            outputHTML(to: path)
        case .text:
            outputText(to: path)
        }
    }
    
    private func outputText(to path: String?) {
        if let path = path {
            write(report: text, to: path, fileExtension: ".txt")
        } else {
            print(text)
            Messenger.success("Text report printed!")
        }
    }
    
    private func outputHTML(to path: String?) {
        let linkModifier = Modifier(target: .links) { html, markdown in
            return html.contains("https://") ? html : String(markdown)
        }
        let parser = MarkdownParser(modifiers: [linkModifier])
        let html = wrapHTML(body: parser.parse(markdown).html.replacingOccurrences(of: "\n", with: ""))
        if let path = path {
            write(report: html, to: path, fileExtension: ".html")
        } else {
            print(html)
            Messenger.success("HTML Report printed!")
        }
    }
    
    private func write(report: String, to path: String, fileExtension: String) {
        guard let path = URL(string: path)?
            .appendingPathComponent(reportFilename)
            .appendingPathExtension(fileExtension).path else {
            Messenger.error("Unable to prase path based on configuration value.")
        }
        
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: report.data(using: .utf8))
            Messenger.success("Report exported to \(path)")
            if Configuration.current.report.openWhenComplete {
                Messenger.success("Opening report...")
                sh("open \(path)")
            }
            
        } else {
            Messenger.error("Couldn't overwrite file.")
        }
    }
}

// MARK: - Text Format

extension Report {
    private var text: String {
        return """
        \(createTextTitle(for: "✅ CommitChecker Report "))
        
        Projects: \(projects)
        Version: \(version)
        Timeline Analyzed: \(startBranch)...\(endBranch)
        Created On: \(createdString)
        
        \(createTextTitle(for: "📋 Summary "))
        
        \(textAnalyzedCountSummary)
        \(textMergeCommitsSummary)
        \(textCommitsWithoutIssuesSummary)
        \(textCommitsWithUnwantedIssuesSummary)
        \(textIncompleteIssuesSummary)
        \(textIssuesWithoutCommitsSummary)
        
        \(createTextTitle(for: "⚠️  Commits Without Issues \(commitsWithoutIssues.count) "))
        
        \(commitsWithoutIssues.map { commit in
            return """
            Author: \(commit.author)
            Message: \(commit.message)
            """
        }.joined(separator: "\n\n"))
        
        \(createTextTitle(for: "⚠️  Commits With Unwanted Issues (\(commitsWithUnwantedIssues.count)) "))
        
        \(commitsWithUnwantedIssues.map { commit in
            return """
            Author: \(commit.author)
            Message: \(commit.message)
            Issues: \(commit.issues.joined(separator: ", "))
            """
        }.joined(separator: "\n\n"))
        
        \(createTextTitle(for: "⚠️  Incomplete Issues (\(incompleteIssues.count)) "))
        
        \(incompleteIssues.map { issue in
            return """
            Issue: \(issue.key)
            Summary: \(issue.fields.summary)
            Status: \(issue.fields.status?.name ?? "No Status")
            Labels: \(issue.fields.labels?.joined(separator: ", ") ?? "No Labels")
            URL: \(issue.url)
            """
        }.joined(separator: "\n\n"))
        
        \(createTextTitle(for: "⚠️  Issues Without Commits (\(issuesWithoutCommits.count)) "))
        
        \(issuesWithoutCommits.map { issue in
            return """
            Issue: \(issue.key)
            Summary: \(issue.fields.summary)
            Status: \(issue.fields.status?.name ?? "No Status")
            Labels: \(issue.fields.labels?.joined(separator: ", ") ?? "No Labels")
            URL: \(issue.url)
            """
        }.joined(separator: "\n\n"))
        
        \(textEndBar)
        """
    }
    
    // MARK: Title
    
    private func createTextTitle(for title: String) -> String {
        let fillerCount = (0..<(Constants.textReportWidth - (Constants.textTitlePrefix.count + title.count)))
        let filler = fillerCount.reduce("") { result, _ in result + "=" }
        return "\(Constants.textTitlePrefix)\(title)\(filler)"
    }
    
    // MARK: Summary
    
    private var textAnalyzedCountSummary: String {
        return "Analyzed \(commits.count) commits and \(issues.count) issues."
    }
    
    private var textMergeCommitsSummary: String {
        let totalMergeCommits = commits.count - nonMergeCommits.count
        return "\(totalMergeCommits) merge commits."
    }
    
    private var textCommitsWithoutIssuesSummary: String {
        let partA = "\(commitsWithoutIssues.count) commits that don't contain an issue."
        let partB = "(\(commitsWithoutIssuesPercentage))"
        return combineTextSummary(partA, and: partB)
    }
    
    private var textCommitsWithUnwantedIssuesSummary: String {
        let partA = "\(commitsWithUnwantedIssues.count) commits for work not in \(version)."
        let partB = "(\(commitsWithUnwantedIssuesPercentage))"
        return combineTextSummary(partA, and: partB)
    }
    
    private var textIncompleteIssuesSummary: String {
        let partA = "\(incompleteIssues.count) incomplete issues."
        let partB = "(\(incompleteIssuesPercentage))"
        return combineTextSummary(partA, and: partB)
    }
    
    private var textIssuesWithoutCommitsSummary: String {
        let partA = "\(issuesWithoutCommits.count) issues not referenced in any commit."
        let partB = "(\(issuesWithoutCommitsPercentage))"
        return combineTextSummary(partA, and: partB)
    }
    
    private func combineTextSummary(_ partA: String, and partB: String) -> String {
        let fillerCount = (0..<(Constants.textReportWidth - (partA.count + partB.count)))
        let fillerString = fillerCount.reduce("") { result, _ in result + "."}
        return "\(partA)\(fillerString)\(partB)"
    }
    
    // MARK: End Bar
    
    private var textEndBar: String {
        return (0..<Constants.textReportWidth).reduce("=") { result, _ in
            result + "="
        }
    }
    
}

// MARK: - Markdown Format

extension Report {
    var markdown: String {
        return """
        # ✅ CommitChecker Report
        **Timeline Analyzed:** `\(startBranch)...\(endBranch)`
        
        **Projects:** `\(projects.joined(separator: ", "))`
        
        **Version:** `\(version)`
        
        **Created On:** `\(createdString)`

        ## 📋 Summary
        - ℹ️ Analyzed \(commits.count) **commits** and \(issues.count) **issues**.
        - ℹ️ \(commits.count - nonMergeCommits.count) merge **commits**.
        - ⚠️ \(commitsWithoutIssues.count) **commits** that don't contain an **issue**.
        - ⚠️ \(commitsWithUnwantedIssues.count) **commits** for work not in **\(version)**.
        - ⚠️ \(incompleteIssues.count) incomplete **issues**.
        - ⚠️ \(issuesWithoutCommits.count) **issues** not referenced in any **commit**.

        ## ⚠️ \(commitsWithoutIssues.count) Commits Without Issues (\(commitsWithoutIssuesPercentage))
        This section lists out work that was commited to the repository that did not directly reference any JIRA issue in the commit message. This could be due a few reasons...
        
        - The author is not using the repository commit script to auto tag their commits.
        - The commit was a small task that did not have an associated ticket.
        
        These commits should be analyzed to make sure that no risk was introduced by their untracked changes.
        
        | Message | Author | Date |
        | ------- | ------ | ---- |
        \(commitsWithoutIssues.map { commit in
            let message = commit.message
            let author = commit.author
            let date = commit.date
            return "| \(message) | \(author) | \(date) |"
        }.joined(separator: "\n"))

        ## ⚠️ \(commitsWithUnwantedIssues.count) Commits With Unwanted Issues (\(commitsWithUnwantedIssuesPercentage))
        This section lists out work that was commited to the repository that referenced a JIRA issue that had a different fix version than the one specified by the script. This could be due to a few reasons...
        
        - Work for a future release was merged into this repository.
        - The JIRA ticket's fix version is wrong.
        
        These commits should be analyzed to make sure that no risk was introduced by their changes.
        
        | Issues | Message | Author | Date |
        | ------ | ------- | ------ | ---- |
        \(commitsWithUnwantedIssues.map { commit -> String in
            let author = commit.author
            let message = commit.message
            let date = commit.date
            let issues = commit.issues.map { issue in
                return "[\(issue)](\(Configuration.current.jira.url)/browse/\(issue))"
            }.joined(separator: ", ")
            return "| \(issues) | \(message) | \(author) | \(date) |"
        }.joined(separator: "\n"))

        ## ⚠️ \(incompleteIssues.count) Incomplete Issues (\(incompleteIssuesPercentage))
        This section lists out the JIRA issues that have not be closed out. This could be due to a few reasons...
        
        - The ticket is still in development
        - The ticket was rejected
        - The ticket is in QA
        - The ticket is in product review
        
        These JIRA issues should be analyzed to make sure that we have no outstanding work to complete before releasing.
        
        | Number   | Summary | Status | Labels  | Asignee |
        | -------- | ------- | ------ | ------- | ------- |
        \(incompleteIssues.map { issue -> String in
            let number = "[\(issue.key)](\(issue.url))"
            let summary = issue.fields.summary
            let status = issue.fields.status?.name ?? "No Status"
            let labels = issue.fields.labels?.compactMap { "`\($0)`" }.joined(separator: " ") ?? "No Labels"
            let asignee = issue.fields.assignee?.displayName ?? "No Asignee"
            return "| \(number) | \(summary) | \(status) | \(labels) | \(asignee) |"
        }.joined(separator: "\n"))
        
        ## ⚠️ \(issuesWithoutCommits.count) Issues Without Commits (\(issuesWithoutCommitsPercentage))
        This section lists JIRA issues that don't have any commits associated with them. This could be due to a few reasons...
        
        - The JIRA issue didn't require any work on the client.
        
        These JIRA issues should be analyzed to make sure that we aren't missing any work that still needs to be complete.
        
        | Number   | Summary  | Status | Labels  | Asignee |
        | -------- | -------- | ------ | ------- | ------- |
        \(issuesWithoutCommits.map { issue -> String in
            let number = "[\(issue.key)](\(issue.url))"
            let summary = issue.fields.summary
            let status = issue.fields.status?.name ?? "No Status"
            let labels = issue.fields.labels?.compactMap { "`\($0)`" }.joined(separator: " ") ?? "No Labels"
            let asignee = issue.fields.assignee?.displayName ?? "No Asignee"
            return "| \(number) | \(summary) | \(status) | \(labels) | \(asignee) |"
        }.joined(separator: "\n"))
        """
    }
    
    private func wrapHTML(body: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
            <head>
                <title>✅ CommitChecker Report</title>
                <style>
                    \(Self.styledCSS)
                </style>
                <base target="_blank">
                <meta charset="UTF-8">
                <meta name="author" content="Connor Ricks">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
            </head>
            <body class="markdown-body">
                \(body)
            </body>
        </html>
        """
    }
    
    private static let styledCSS: String = """
    .markdown-body .octicon{display:inline-block;fill:currentColor;vertical-align:text-bottom}.markdown-body .anchor{float:left;line-height:1;margin-left:-20px;padding-right:4px}.markdown-body .anchor:focus{outline:0}.markdown-body h1 .octicon-link,.markdown-body h2 .octicon-link,.markdown-body h3 .octicon-link,.markdown-body h4 .octicon-link,.markdown-body h5 .octicon-link,.markdown-body h6 .octicon-link{color:#1b1f23;vertical-align:middle;visibility:hidden}.markdown-body h1:hover .anchor,.markdown-body h2:hover .anchor,.markdown-body h3:hover .anchor,.markdown-body h4:hover .anchor,.markdown-body h5:hover .anchor,.markdown-body h6:hover .anchor{text-decoration:none}.markdown-body h1:hover .anchor .octicon-link,.markdown-body h2:hover .anchor .octicon-link,.markdown-body h3:hover .anchor .octicon-link,.markdown-body h4:hover .anchor .octicon-link,.markdown-body h5:hover .anchor .octicon-link,.markdown-body h6:hover .anchor .octicon-link{visibility:visible}.markdown-body h1:hover .anchor .octicon-link:before,.markdown-body h2:hover .anchor .octicon-link:before,.markdown-body h3:hover .anchor .octicon-link:before,.markdown-body h4:hover .anchor .octicon-link:before,.markdown-body h5:hover .anchor .octicon-link:before,.markdown-body h6:hover .anchor .octicon-link:before{width:16px;height:16px;content:' ';display:inline-block;background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' version='1.1' width='16' height='16' aria-hidden='true'%3E%3Cpath fill-rule='evenodd' d='M4 9h1v1H4c-1.5 0-3-1.69-3-3.5S2.55 3 4 3h4c1.45 0 3 1.69 3 3.5 0 1.41-.91 2.72-2 3.25V8.59c.58-.45 1-1.27 1-2.09C10 5.22 8.98 4 8 4H4c-.98 0-2 1.22-2 2.5S3 9 4 9zm9-3h-1v1h1c1 0 2 1.22 2 2.5S13.98 12 13 12H9c-.98 0-2-1.22-2-2.5 0-.83.42-1.64 1-2.09V6.25c-1.09.53-2 1.84-2 3.25C6 11.31 7.55 13 9 13h4c1.45 0 3-1.69 3-3.5S14.5 6 13 6z'%3E%3C/path%3E%3C/svg%3E")}.markdown-body{-ms-text-size-adjust:100%;-webkit-text-size-adjust:100%;line-height:1.5;color:#24292e;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Helvetica,Arial,sans-serif,Apple Color Emoji,Segoe UI Emoji;font-size:16px;line-height:1.5;word-wrap:break-word}.markdown-body details{display:block}.markdown-body summary{display:list-item}.markdown-body a{background-color:initial}.markdown-body a:active,.markdown-body a:hover{outline-width:0}.markdown-body strong{font-weight:inherit;font-weight:bolder}.markdown-body h1{font-size:2em;margin:.67em 0}.markdown-body img{border-style:none}.markdown-body code,.markdown-body kbd,.markdown-body pre{font-family:monospace,monospace;font-size:1em}.markdown-body hr{box-sizing:initial;height:0;overflow:visible}.markdown-body input{font:inherit;margin:0}.markdown-body input{overflow:visible}.markdown-body [type=checkbox]{box-sizing:border-box;padding:0}.markdown-body *{box-sizing:border-box}.markdown-body input{font-family:inherit;font-size:inherit;line-height:inherit}.markdown-body a{color:#0366d6;text-decoration:none}.markdown-body a:hover{text-decoration:underline}.markdown-body strong{font-weight:600}.markdown-body hr{height:0;margin:15px 0;overflow:hidden;background:0 0;border:0;border-bottom:1px solid #dfe2e5}.markdown-body hr:after,.markdown-body hr:before{display:table;content:""}.markdown-body hr:after{clear:both}.markdown-body table{border-spacing:0;border-collapse:collapse}.markdown-body td,.markdown-body th{padding:0}.markdown-body details summary{cursor:pointer}.markdown-body kbd{display:inline-block;padding:3px 5px;font:11px SFMono-Regular,Consolas,Liberation Mono,Menlo,monospace;line-height:10px;color:#444d56;vertical-align:middle;background-color:#fafbfc;border:1px solid #d1d5da;border-radius:3px;box-shadow:inset 0 -1px 0 #d1d5da}.markdown-body h1,.markdown-body h2,.markdown-body h3,.markdown-body h4,.markdown-body h5,.markdown-body h6{margin-top:0;margin-bottom:0}.markdown-body h1{font-size:32px}.markdown-body h1,.markdown-body h2{font-weight:600}.markdown-body h2{font-size:24px}.markdown-body h3{font-size:20px}.markdown-body h3,.markdown-body h4{font-weight:600}.markdown-body h4{font-size:16px}.markdown-body h5{font-size:14px}.markdown-body h5,.markdown-body h6{font-weight:600}.markdown-body h6{font-size:12px}.markdown-body p{margin-top:0;margin-bottom:10px}.markdown-body blockquote{margin:0}.markdown-body ol,.markdown-body ul{padding-left:0;margin-top:0;margin-bottom:0}.markdown-body ol ol,.markdown-body ul ol{list-style-type:lower-roman}.markdown-body ol ol ol,.markdown-body ol ul ol,.markdown-body ul ol ol,.markdown-body ul ul ol{list-style-type:lower-alpha}.markdown-body dd{margin-left:0}.markdown-body code,.markdown-body pre{font-family:SFMono-Regular,Consolas,Liberation Mono,Menlo,monospace;font-size:12px}.markdown-body pre{margin-top:0;margin-bottom:0}.markdown-body input::-webkit-inner-spin-button,.markdown-body input::-webkit-outer-spin-button{margin:0;-webkit-appearance:none;appearance:none}.markdown-body :checked+.radio-label{position:relative;z-index:1;border-color:#0366d6}.markdown-body .border{border:1px solid #e1e4e8!important}.markdown-body .border-0{border:0!important}.markdown-body .border-bottom{border-bottom:1px solid #e1e4e8!important}.markdown-body .rounded-1{border-radius:3px!important}.markdown-body .bg-white{background-color:#fff!important}.markdown-body .bg-gray-light{background-color:#fafbfc!important}.markdown-body .text-gray-light{color:#6a737d!important}.markdown-body .mb-0{margin-bottom:0!important}.markdown-body .my-2{margin-top:8px!important;margin-bottom:8px!important}.markdown-body .pl-0{padding-left:0!important}.markdown-body .py-0{padding-top:0!important;padding-bottom:0!important}.markdown-body .pl-1{padding-left:4px!important}.markdown-body .pl-2{padding-left:8px!important}.markdown-body .py-2{padding-top:8px!important;padding-bottom:8px!important}.markdown-body .pl-3,.markdown-body .px-3{padding-left:16px!important}.markdown-body .px-3{padding-right:16px!important}.markdown-body .pl-4{padding-left:24px!important}.markdown-body .pl-5{padding-left:32px!important}.markdown-body .pl-6{padding-left:40px!important}.markdown-body .f6{font-size:12px!important}.markdown-body .lh-condensed{line-height:1.25!important}.markdown-body .text-bold{font-weight:600!important}.markdown-body .pl-c{color:#6a737d}.markdown-body .pl-c1,.markdown-body .pl-s .pl-v{color:#005cc5}.markdown-body .pl-e,.markdown-body .pl-en{color:#6f42c1}.markdown-body .pl-s .pl-s1,.markdown-body .pl-smi{color:#24292e}.markdown-body .pl-ent{color:#22863a}.markdown-body .pl-k{color:#d73a49}.markdown-body .pl-pds,.markdown-body .pl-s,.markdown-body .pl-s .pl-pse .pl-s1,.markdown-body .pl-sr,.markdown-body .pl-sr .pl-cce,.markdown-body .pl-sr .pl-sra,.markdown-body .pl-sr .pl-sre{color:#032f62}.markdown-body .pl-smw,.markdown-body .pl-v{color:#e36209}.markdown-body .pl-bu{color:#b31d28}.markdown-body .pl-ii{color:#fafbfc;background-color:#b31d28}.markdown-body .pl-c2{color:#fafbfc;background-color:#d73a49}.markdown-body .pl-c2:before{content:"^M"}.markdown-body .pl-sr .pl-cce{font-weight:700;color:#22863a}.markdown-body .pl-ml{color:#735c0f}.markdown-body .pl-mh,.markdown-body .pl-mh .pl-en,.markdown-body .pl-ms{font-weight:700;color:#005cc5}.markdown-body .pl-mi{font-style:italic;color:#24292e}.markdown-body .pl-mb{font-weight:700;color:#24292e}.markdown-body .pl-md{color:#b31d28;background-color:#ffeef0}.markdown-body .pl-mi1{color:#22863a;background-color:#f0fff4}.markdown-body .pl-mc{color:#e36209;background-color:#ffebda}.markdown-body .pl-mi2{color:#f6f8fa;background-color:#005cc5}.markdown-body .pl-mdr{font-weight:700;color:#6f42c1}.markdown-body .pl-ba{color:#586069}.markdown-body .pl-sg{color:#959da5}.markdown-body .pl-corl{text-decoration:underline;color:#032f62}.markdown-body .mb-0{margin-bottom:0!important}.markdown-body .my-2{margin-bottom:8px!important}.markdown-body .my-2{margin-top:8px!important}.markdown-body .pl-0{padding-left:0!important}.markdown-body .py-0{padding-top:0!important;padding-bottom:0!important}.markdown-body .pl-1{padding-left:4px!important}.markdown-body .pl-2{padding-left:8px!important}.markdown-body .py-2{padding-top:8px!important;padding-bottom:8px!important}.markdown-body .pl-3{padding-left:16px!important}.markdown-body .pl-4{padding-left:24px!important}.markdown-body .pl-5{padding-left:32px!important}.markdown-body .pl-6{padding-left:40px!important}.markdown-body .pl-7{padding-left:48px!important}.markdown-body .pl-8{padding-left:64px!important}.markdown-body .pl-9{padding-left:80px!important}.markdown-body .pl-10{padding-left:96px!important}.markdown-body .pl-11{padding-left:112px!important}.markdown-body .pl-12{padding-left:128px!important}.markdown-body hr{border-bottom-color:#eee}.markdown-body kbd{display:inline-block;padding:3px 5px;font:11px SFMono-Regular,Consolas,Liberation Mono,Menlo,monospace;line-height:10px;color:#444d56;vertical-align:middle;background-color:#fafbfc;border:1px solid #d1d5da;border-radius:3px;box-shadow:inset 0 -1px 0 #d1d5da}.markdown-body:after,.markdown-body:before{display:table;content:""}.markdown-body:after{clear:both}.markdown-body>:first-child{margin-top:0!important}.markdown-body>:last-child{margin-bottom:0!important}.markdown-body a:not([href]){color:inherit;text-decoration:none}.markdown-body blockquote,.markdown-body details,.markdown-body dl,.markdown-body ol,.markdown-body p,.markdown-body pre,.markdown-body table,.markdown-body ul{margin-top:0;margin-bottom:16px}.markdown-body hr{height:.25em;padding:0;margin:24px 0;background-color:#e1e4e8;border:0}.markdown-body blockquote{padding:0 1em;color:#6a737d;border-left:.25em solid #dfe2e5}.markdown-body blockquote>:first-child{margin-top:0}.markdown-body blockquote>:last-child{margin-bottom:0}.markdown-body h1,.markdown-body h2,.markdown-body h3,.markdown-body h4,.markdown-body h5,.markdown-body h6{margin-top:24px;margin-bottom:16px;font-weight:600;line-height:1.25}.markdown-body h1{font-size:2em}.markdown-body h1,.markdown-body h2{padding-bottom:.3em;border-bottom:1px solid #eaecef}.markdown-body h2{font-size:1.5em}.markdown-body h3{font-size:1.25em}.markdown-body h4{font-size:1em}.markdown-body h5{font-size:.875em}.markdown-body h6{font-size:.85em;color:#6a737d}.markdown-body ol,.markdown-body ul{padding-left:2em}.markdown-body ol ol,.markdown-body ol ul,.markdown-body ul ol,.markdown-body ul ul{margin-top:0;margin-bottom:0}.markdown-body li{word-wrap:break-all}.markdown-body li>p{margin-top:16px}.markdown-body li+li{margin-top:.25em}.markdown-body dl{padding:0}.markdown-body dl dt{padding:0;margin-top:16px;font-size:1em;font-style:italic;font-weight:600}.markdown-body dl dd{padding:0 16px;margin-bottom:16px}.markdown-body table{display:block;width:100%;overflow:auto}.markdown-body table th{font-weight:600}.markdown-body table td,.markdown-body table th{padding:6px 13px;border:1px solid #dfe2e5}.markdown-body table tr{background-color:#fff;border-top:1px solid #c6cbd1}.markdown-body table tr:nth-child(2n){background-color:#f6f8fa}.markdown-body img{max-width:100%;box-sizing:initial;background-color:#fff}.markdown-body img[align=right]{padding-left:20px}.markdown-body img[align=left]{padding-right:20px}.markdown-body code{padding:.2em .4em;margin:0;font-size:85%;background-color:rgba(27,31,35,.05);border-radius:3px}.markdown-body pre{word-wrap:normal}.markdown-body pre>code{padding:0;margin:0;font-size:100%;word-break:normal;white-space:pre;background:0 0;border:0}.markdown-body .highlight{margin-bottom:16px}.markdown-body .highlight pre{margin-bottom:0;word-break:normal}.markdown-body .highlight pre,.markdown-body pre{padding:16px;overflow:auto;font-size:85%;line-height:1.45;background-color:#f6f8fa;border-radius:3px}.markdown-body pre code{display:inline;max-width:auto;padding:0;margin:0;overflow:visible;line-height:inherit;word-wrap:normal;background-color:initial;border:0}.markdown-body .commit-tease-sha{display:inline-block;font-family:SFMono-Regular,Consolas,Liberation Mono,Menlo,monospace;font-size:90%;color:#444d56}.markdown-body .full-commit .btn-outline:not(:disabled):hover{color:#005cc5;border-color:#005cc5}.markdown-body .blob-wrapper{overflow-x:auto;overflow-y:hidden}.markdown-body .blob-wrapper-embedded{max-height:240px;overflow-y:auto}.markdown-body .blob-num{width:1%;min-width:50px;padding-right:10px;padding-left:10px;font-family:SFMono-Regular,Consolas,Liberation Mono,Menlo,monospace;font-size:12px;line-height:20px;color:rgba(27,31,35,.3);text-align:right;white-space:nowrap;vertical-align:top;cursor:pointer;-webkit-user-select:none;-moz-user-select:none;-ms-user-select:none;user-select:none}.markdown-body .blob-num:hover{color:rgba(27,31,35,.6)}.markdown-body .blob-num:before{content:attr(data-line-number)}.markdown-body .blob-code{position:relative;padding-right:10px;padding-left:10px;line-height:20px;vertical-align:top}.markdown-body .blob-code-inner{overflow:visible;font-family:SFMono-Regular,Consolas,Liberation Mono,Menlo,monospace;font-size:12px;color:#24292e;word-wrap:normal;white-space:pre}.markdown-body .pl-token.active,.markdown-body .pl-token:hover{cursor:pointer;background:#ffea7f}.markdown-body .tab-size[data-tab-size="1"]{-moz-tab-size:1;tab-size:1}.markdown-body .tab-size[data-tab-size="2"]{-moz-tab-size:2;tab-size:2}.markdown-body .tab-size[data-tab-size="3"]{-moz-tab-size:3;tab-size:3}.markdown-body .tab-size[data-tab-size="4"]{-moz-tab-size:4;tab-size:4}.markdown-body .tab-size[data-tab-size="5"]{-moz-tab-size:5;tab-size:5}.markdown-body .tab-size[data-tab-size="6"]{-moz-tab-size:6;tab-size:6}.markdown-body .tab-size[data-tab-size="7"]{-moz-tab-size:7;tab-size:7}.markdown-body .tab-size[data-tab-size="8"]{-moz-tab-size:8;tab-size:8}.markdown-body .tab-size[data-tab-size="9"]{-moz-tab-size:9;tab-size:9}.markdown-body .tab-size[data-tab-size="10"]{-moz-tab-size:10;tab-size:10}.markdown-body .tab-size[data-tab-size="11"]{-moz-tab-size:11;tab-size:11}.markdown-body .tab-size[data-tab-size="12"]{-moz-tab-size:12;tab-size:12}.markdown-body .task-list-item{list-style-type:none}.markdown-body .task-list-item+.task-list-item{margin-top:3px}.markdown-body .task-list-item input{margin:0 .2em .25em -1.6em;vertical-align:middle}
    """
}

// MARK: - Report Creation Helpers

extension Report {
    private static func commitsWithUnwantedIssues(commits: [GitCommit], issues: [JiraIssue]) -> [GitCommit] {
            return commits.filter { commit in
                guard !commit.issues.isEmpty else {
                    return false /// The commit contains no issues. (Filter out)
                }
                
                for commitIssue in commit.issues {
                    for jiraIssue in issues {
                        if commitIssue == jiraIssue.key {
                            return false /// This  commit contains this jiraIssue. (Filter out)
                        }
                    }
                }
                
                return true
            }
        }
        
    private static func issuesWithoutCommits(commits: [GitCommit], issues: [JiraIssue]) -> [JiraIssue] {
        return issues.filter { jiraIssue in
            for commit in commits {
                for commitIssue in commit.issues {
                    if commitIssue == jiraIssue.key {
                        return false /// This commit contains this jiraIssue. (Filter out)
                    }
                }
            }

            return true /// No commits contain this jira issue. (Keep)
        }
    }
}

fileprivate extension Array where Element == GitCommit {
    var nonMergeCommits: [GitCommit] {
        filter { !$0.isMerge }
    }
    
    var commitsWithoutIssues: [GitCommit] {
        filter { $0.issues.isEmpty }
    }
}

fileprivate extension Array where Element == JiraIssue {
    var incompleteIssues: [JiraIssue]  {
        filter { !($0.fields.status?.isComplete ?? false) }
    }
}
