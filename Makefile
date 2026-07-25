.PHONY: dev release deploy

dev:
	cd example && flutter run -d chrome

release:
	cd example && flutter run -d chrome --release

deploy:
	cd example && flutter build web --release && npx wrangler pages deploy build/web --project-name infinite-lazy-grid --branch main
