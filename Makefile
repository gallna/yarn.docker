include make.docker/hub.docker.mk

NAME = $(NS)/$(PROJECT)

hadoop = $(NAME).hadoop:$(current_version)
spark = $(NAME).spark:2.1.0-$(current_build)

.PHONY: hadoop spark

hadoop:
	$(MAKE) $@-build
	$(MAKE) $@-push

spark:
	$(MAKE) $@-build
	$(MAKE) $@-push

%-push:
	docker push $($*)
	docker push $(NAME).$*:$(current_tag)
	docker push $(NAME).$*:latest

%-build:
	docker build -t $($*) --file=Dockerfile.$* .
	docker tag $($*) $(NAME).$*:$(current_tag)
	docker tag $($*) $(NAME).$*:latest
