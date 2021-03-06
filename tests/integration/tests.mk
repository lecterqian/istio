#-----------------------------------------------------------------------------
# Target: test.integration.*
#-----------------------------------------------------------------------------

# The following flags (in addition to ${V}) can be specified on the command-line, or the environment. This
# is primarily used by the CI systems.
_INTEGRATION_TEST_FLAGS ?= $(INTEGRATION_TEST_FLAGS)

# $(CI) specifies that the test is running in a CI system. This enables CI specific logging.
ifneq ($(CI),)
	_INTEGRATION_TEST_FLAGS += --istio.test.ci
	_INTEGRATION_TEST_FLAGS += --istio.test.pullpolicy=IfNotPresent
endif

ifeq ($(TEST_ENV),minikube)
    _INTEGRATION_TEST_FLAGS += --istio.test.kube.minikube
else ifeq ($(TEST_ENV),minikube-none)
    _INTEGRATION_TEST_FLAGS += --istio.test.kube.minikube
else ifeq ($(TEST_ENV),kind)
    _INTEGRATION_TEST_FLAGS += --istio.test.kube.minikube
endif

ifneq ($(ARTIFACTS),)
    _INTEGRATION_TEST_FLAGS += --istio.test.work_dir=$(ARTIFACTS)
endif

ifneq ($(HUB),)
    _INTEGRATION_TEST_FLAGS += --istio.test.hub=$(HUB)
endif

ifneq ($(TAG),)
    _INTEGRATION_TEST_FLAGS += --istio.test.tag=$(TAG)
endif

# $(INTEGRATION_TEST_KUBECONFIG) specifies the kube config file to be used. If not specified, then
# ~/.kube/config is used.
# TODO: This probably needs to be more intelligent and take environment variables into account.
ifneq ($(KUBECONFIG),)
	_INTEGRATION_TEST_FLAGS += --istio.test.kube.config=$(KUBECONFIG)
else
	_INTEGRATION_TEST_FLAGS += --istio.test.kube.config=~/.kube/config
endif

# Generate integration test targets for kubernetes environment.
test.integration.%.kube: | $(JUNIT_REPORT)
	$(GO) test -p 1 ${T} ./tests/integration/$(subst .,/,$*)/... -timeout 30m \
	--istio.test.env kube \
	${_INTEGRATION_TEST_FLAGS} \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))

# filter out non-standard test directories
TEST_PACKAGES = $(shell go list ./tests/integration/... | grep -v /qualification | grep -v /examples | grep -v /istioio)

# Generate integration test targets for local environment.
test.integration.%.local: | $(JUNIT_REPORT)
	$(GO) test -p 1 ${T} -race ./tests/integration/$(subst .,/,$*)/... \
	--istio.test.env native \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))

# Generate presubmit integration test targets for each component in kubernetes environment
test.integration.%.kube.presubmit: istioctl | $(JUNIT_REPORT)
	PATH=${PATH}:${ISTIO_OUT} $(GO) test -p 1 ${T} ./tests/integration/$(subst .,/,$*)/... -timeout 30m \
	--istio.test.select -postsubmit,-flaky \
	--istio.test.env kube \
	${_INTEGRATION_TEST_FLAGS} \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))

test.integration.istioio.kube.presubmit: istioctl | $(JUNIT_REPORT)
	PATH=${PATH}:${ISTIO_OUT} $(GO) test -p 1 ${T} ./tests/integration/istioio/... -timeout 30m \
	--istio.test.select -postsubmit,-flaky \
	--istio.test.kube.operator=false \
	--istio.test.env kube \
	${_INTEGRATION_TEST_FLAGS} \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))

test.integration.istioio.kube.postsubmit: test.integration.istioio.kube.presubmit
	SNIPPETS_GCS_PATH="istio-snippets/$(shell git rev-parse HEAD)" prow/upload-istioio-snippets.sh

# Generate presubmit integration test targets for each component in local environment.
test.integration.%.local.presubmit: | $(JUNIT_REPORT)
	$(GO) test -p 1 ${T} -race ./tests/integration/$(subst .,/,$*)/... \
	--istio.test.env native --istio.test.select -postsubmit,-flaky \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))

# Presubmit integration tests targeting Kubernetes environment.
.PHONY: test.integration.kube.presubmit
test.integration.kube.presubmit: istioctl | $(JUNIT_REPORT)
	PATH=${PATH}:${ISTIO_OUT} $(GO) test -p 1 ${T} ${TEST_PACKAGES} -timeout 30m \
    --istio.test.select -postsubmit,-flaky \
 	--istio.test.env kube \
	${_INTEGRATION_TEST_FLAGS} \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))

# Defines a target to run a minimal reachability testing basic traffic
.PHONY: test.integration.kube.reachability
test.integration.kube.reachability: istioctl | $(JUNIT_REPORT)
	PATH=${PATH}:${ISTIO_OUT} $(GO) test -p 1 ${T} ./tests/integration/security/ -timeout 30m \
	--istio.test.env kube \
	${_INTEGRATION_TEST_FLAGS} \
	--test.run=TestReachability \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))
