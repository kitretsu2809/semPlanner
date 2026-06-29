#!/bin/bash

# Remove any existing git config if we want to reset (but we are already in an empty repo)

git config user.name "kitretsu2809"
git config user.email "kitretsu2809@users.noreply.github.com"

# Commit 1: Initial setup
git add pubspec.yaml pubspec.lock analysis_options.yaml README.md .metadata .gitignore
git add android/ ios/ linux/ macos/ web/ windows/ test/
git commit -m "Initial Flutter project setup and platform configurations"

# Commit 2: Core configuration and models
git add lib/core/models/ lib/core/theme.dart lib/core/providers/
git commit -m "Add core theme, data models, and Riverpod providers"

# Commit 3: Routing and services
git add lib/core/router.dart lib/core/services/
git commit -m "Setup GoRouter and core AI/Database services"

# Commit 4: Auth & Onboarding
git add lib/features/auth/ lib/features/onboarding/
git commit -m "Implement authentication screens and syllabus intake flow"

# Commit 5: Dashboard and main
git add lib/features/dashboard/ lib/main.dart
git commit -m "Build dashboard UI and weekly schedule viewer"

# Commit 6: AI Hub and Roadmap
git add lib/features/ai_hub/ lib/features/roadmap/
git commit -m "Integrate AI Hub and roadmap generation features"

# Commit 7: Assets and docs
git add assets/ docs/ firebase.json
git commit -m "Add app icons, firebase config, and landing page docs"

# Add remote and push
git branch -M main
git remote add origin git@github.com:kitretsu2809/semPlanner.git
git push -u origin main -f

