.PHONY: dev release build deploy

dev:
	cd example && flutter run -d chrome

release:
	cd example && flutter run -d chrome --release

build:
	cd example && flutter build web --release

deploy: build
	npx --yes wrangler@4.104.0 pages deploy example/build/web --project-name infinite-lazy-grid
