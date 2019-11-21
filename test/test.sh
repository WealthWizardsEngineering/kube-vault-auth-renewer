#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source ${DIR}/utils.sh

TEST_SUITE_RESULT=0

echo "Waiting for test data to load..."
sleep 10

source ${DIR}/tests/testVaultTokenCanBeRenewed.sh || TEST_SUITE_RESULT=1
source ${DIR}/tests/testEmptyLeaseIds.sh || TEST_SUITE_RESULT=1
source ${DIR}/tests/testSingleLeaseCanBeRenewed.sh || TEST_SUITE_RESULT=1
source ${DIR}/tests/testErrorReturnedWhenNoTokenProvided.sh || TEST_SUITE_RESULT=1
source ${DIR}/tests/testErrorReturnedWhenVaultAuthenticationFails.sh || TEST_SUITE_RESULT=1

if [[ "TEST_SUITE_RESULT" -gt 0 ]]; then
    printf "\n************************\n"
    printf "FAIL: There were test failures, inspect the details above for details\n"
fi

exit ${TEST_SUITE_RESULT}
