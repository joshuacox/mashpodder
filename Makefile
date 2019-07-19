all: build run

build:
	docker build -t joshuacox/mashpodder .

run: .PODCASTS.dir
	$(eval PODCASTS := $(shell cat .PODCASTS.dir))
	docker run \
		-it \
		-v "${PODCASTS}:/mashpodder/PODCASTS" \
		-it \
		joshuacox/mashpodder

.PODCASTS.dir:
	@while [ -z "$$PODCASTS" ]; do \
		read -r -p "Enter the destination of the podcasts directory you wish to associate with this container [PODCASTS]: " PODCASTS; echo "$$PODCASTS">>.PODCASTS.dir; cat .PODCASTS.dir; \
	done ;
