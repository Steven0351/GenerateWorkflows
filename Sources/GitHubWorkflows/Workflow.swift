//
//  File.swift
//  
//
//  Created by Steven Sherry on 10/24/19.
//

import Foundation
import SPMUtility

struct Workflow {
  private let fileManager = FileManager.default
  
  let parser: ArgumentParser
  
  let sourceDirectory: OptionArgument<String>
  let projectName: OptionArgument<String>
  let ci: OptionArgument<Bool>
  let docsGeneration: OptionArgument<Bool>
  let githubUrl: OptionArgument<String>
  
  init() {
    parser = ArgumentParser(
      usage: "[options]",
      overview: """
      Generate GitHub Workflow BoilerPlate
      """
    )

    sourceDirectory = parser.add(
      option: "--directory",
      shortName: "-d",
      kind: String.self,
      usage: "--directory /path/to/source/root"
    )
    
    projectName = parser.add(
      option: "--project-name",
      shortName: "-p",
      kind: String.self
    )
    
    ci = parser.add(
      option: "--continuous-integration",
      shortName: "-c",
      kind: Bool.self
    )
    
    docsGeneration = parser.add(
      option: "--generate-documentation",
      shortName: "-d",
      kind: Bool.self
    )
    
    githubUrl = parser.add(
      option: "--github-url",
      shortName: "-g",
      kind: String.self
    )
  }
  
  func run(with args: [String]) throws {
    let args = try parser.parse(Array(args.dropFirst()))
    
    let (base, workflowUrl) = try createWorkflowDirectory(args)
    let name = args.get(projectName) ?? workflowUrl.lastPathComponent
    try createCiDefinition(for: name, at: workflowUrl, with: args)
    try createJazzyYml(for: name, at: base, with: args)
    try createDocsGenerationDefinition(for: name, at: workflowUrl, with: args)
  }
  
  private func createWorkflowDirectory(_ args: ArgumentParser.Result) throws -> (base: Foundation.URL, workflow: Foundation.URL) {
    guard let directory = args.get(sourceDirectory) else {
      print("No directory provided. Exiting...")
      exit(1)
    }

    let cwd = fileManager.currentDirectoryPath
    let url: Foundation.URL = {
      if directory.hasPrefix("/Users") {
        return URL(fileURLWithPath: directory, isDirectory: true)
      } else {
        return URL(fileURLWithPath: directory, isDirectory: true, relativeTo: URL(fileURLWithPath: cwd))
      }
    }()

    let workflowsDirectory = url.appendingPathComponent(".github").appendingPathComponent("workflows")

    try fileManager.createDirectory(at: workflowsDirectory, withIntermediateDirectories: true)

    return (base: url, workflow: workflowsDirectory)
  }
  
  private func createCiDefinition(for projectName: String, at url: Foundation.URL, with args: ArgumentParser.Result) throws {
    if let _ = args.get(ci) {
      let ciYaml = """
      name: CI
      
      on:
        push:
          paths-ignore:
          - "*.md"
        pull_request:
          paths-ignore:
          - "*.md"
      
      jobs:
        build:
          runs-on: macOS-latest
          steps:
            - uses: actions/checkout@v1
            - name: Switch to Xcode 11.0
              run: sudo xcode-select --switch /Applications/Xcode_11.app/Contents/Developer
            - name: Generate Xcode Project - Needed because Combine is not available on Mojave
              run: swift package generate-xcodeproj
            - name: Run iOS Framework Tests
              run: >-
                xcodebuild -project \(projectName).xcodeproj
                -scheme \(projectName)-Package
                -sdk iphonesimulator
                -destination 'platform=iOS Simulator,name=iPhone 11,OS=13.0'
                test | xcpretty
      
      """
      try ciYaml.write(to: url.appendingPathComponent("main.yml"), atomically: true, encoding: .utf8)
    }
  }
  
  private func createJazzyYml(for projectName: String, at url: Foundation.URL, with args: ArgumentParser.Result) throws {
    if let _ = args.get(docsGeneration) {
      var jazzyYaml = """
      clean: true
      sdk: iphone
      author: Steven Sherry
      module: \(projectName)
      readme: README.md
      """
      if let githubUrl = args.get(githubUrl) {
        jazzyYaml += """
        
        github_url: \(githubUrl)
        """
      }
      jazzyYaml += """
      
      disable_search: true
      theme: fullwidth
      build_tool_arguments: [-target, \(projectName)]
      """
      
      try jazzyYaml.write(to: url.appendingPathComponent(".jazzy.yml"), atomically: true, encoding: .utf8)
    }
  }
  
  private func createDocsGenerationDefinition(for projectName: String, at url: Foundation.URL, with args: ArgumentParser.Result) throws {
    if let _ = args.get(docsGeneration) {
      let docGenYaml = """
        name: Publish Documentation

        on:
          release:
            types: [published]

        jobs:
          publish_docs:
            runs-on: macOS-latest
            steps:
              - uses: actions/checkout@v1
              - name: Switch to Xcode 11
                run: sudo xcode-select --switch /Applications/Xcode_11.app/Contents/Developer
              - name: Generate Xcode Project - Needed because Combine is not available on Mojave
                run: swift package generate-xcodeproj
              - name: Publish Jazzy Docs
                uses: steven0351/publish-jazzy-docs@v1
                with:
                  personal_access_token: ${{ secrets.ACCESS_TOKEN }}
                  config: .jazzy.yml

        """
      
      try docGenYaml.write(to: url.appendingPathComponent("docsGen.yml"), atomically: true, encoding: .utf8)
    }
  }
  
}
