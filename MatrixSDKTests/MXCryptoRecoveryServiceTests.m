/*
 Copyright 2020 The Matrix.org Foundation C.I.C
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import <XCTest/XCTest.h>

#import "MXCrypto_Private.h"
#import "MXMemoryStore.h"

#import "MatrixSDKTestsData.h"
#import "MatrixSDKTestsE2EData.h"

@interface MXCryptoRecoveryServiceTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;
}

@end


@implementation MXCryptoRecoveryServiceTests

- (void)setUp
{
    [super setUp];
    
    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
    matrixSDKTestsE2EData = [[MatrixSDKTestsE2EData alloc] initWithMatrixSDKTestsData:matrixSDKTestsData];
}

- (void)tearDown
{
    matrixSDKTestsData = nil;
    matrixSDKTestsE2EData = nil;
}


#pragma mark - Scenarii

// - Create Alice
// - Bootstrap cross-singing on Alice using password
- (void)doTestWithBootstrappedAlice:(XCTestCase*)testCase
                              readyToTest:(void (^)(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    // - Create Alice
    [matrixSDKTestsE2EData doE2ETestWithAliceInARoom:testCase andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {

         // - Bootstrap cross-singing on Alice using password
         [aliceSession.crypto.crossSigning bootstrapWithPassword:MXTESTS_ALICE_PWD success:^{
             
             readyToTest(aliceSession, roomId, expectation);
             
         } failure:^(NSError *error) {
             XCTFail(@"Cannot set up intial test conditions - error: %@", error);
             [expectation fulfill];
         }];
     }];
}

// Test the recovery creation and its restoration.
//
// - Test creation of a recovery
// - Have Alice with cross-signing bootstrapped
// -> There should be no recovery on the HS
// -> The service should see 3 keys to back up (MSK, SSK, USK)
// Create a recovery with a passphrase
// -> The 3 keys should be in the recovery
// -> The recovery must indicate it has a passphrase
// Recover all secrets
// -> We should have restored the 3 ones
// -> Make sure the secret is still correct
- (void)testRecoveryWithPassphrase
{
    // - Have Alice with cross-signing bootstrapped
    [self doTestWithBootstrappedAlice:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        NSString *msk = [aliceSession.crypto.store secretWithSecretId:MXSecretId.crossSigningMaster];

        MXRecoveryService *recoveryService = aliceSession.crypto.recoveryService;
        XCTAssertNotNil(recoveryService);

        // -> There should be no recovery on the HS
        XCTAssertFalse(recoveryService.hasRecovery);
        XCTAssertEqual(recoveryService.storedSecrets.count, 0);
        
        // -> The service should see 3 keys to back up (MSK, SSK, USK)
        XCTAssertEqual(recoveryService.locallyStoredSecrets.count, 3);
        
        // Create a recovery with a passphrase
        NSString *passphrase = @"A passphrase";
        [recoveryService createRecoveryForSecrets:nil withPassphrase:passphrase success:^(MXSecretStorageKeyCreationInfo * _Nonnull keyCreationInfo) {
            
            XCTAssertNotNil(keyCreationInfo);
            
            // -> The 3 keys should be in the recovery
            XCTAssertTrue(recoveryService.hasRecovery);
            XCTAssertEqual(recoveryService.storedSecrets.count, 3);
            
            // -> The recovery must indicate it has a passphrase
            XCTAssertTrue(recoveryService.usePassphrase);
            

            // Recover all secrets
            [recoveryService privateKeyFromPassphrase:passphrase success:^(NSData * _Nonnull privateKey) {
                [recoveryService recoverSecrets:nil withPrivateKey:privateKey success:^(MXSecretRecoveryResult * _Nonnull recoveryResult) {
                    
                    // -> We should have restored the 3 ones
                    XCTAssertEqual(recoveryResult.secrets.count, 3);
                    XCTAssertEqual(recoveryResult.updatedSecrets.count, 0);
                    XCTAssertEqual(recoveryResult.invalidSecrets.count, 0);
                    
                    // -> Make sure the secret is still correct
                    NSString *msk2 = [aliceSession.crypto.store secretWithSecretId:MXSecretId.crossSigningMaster];
                    XCTAssertEqualObjects(msk, msk2);
                    
                    [expectation fulfill];
                } failure:^(NSError * _Nonnull error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
            } failure:^(NSError * _Nonnull error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

// Test privateKeyFromRecoveryKey & privateKeyFromPassphrase
//
// - Have Alice with cross-signing bootstrapped
// Create a recovery with a passphrase
// -> privateKeyFromRecoveryKey must return the same private key
// -> privateKeyFromPassphrase must return the same private key
- (void)testPrivateKeyTools
{
    // - Have Alice with cross-signing bootstrapped
    [self doTestWithBootstrappedAlice:self readyToTest:^(MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation) {
        
        MXRecoveryService *recoveryService = aliceSession.crypto.recoveryService;
        
        // Create a recovery with a passphrase
        NSString *passphrase = @"A passphrase";
        [recoveryService createRecoveryForSecrets:nil withPassphrase:passphrase success:^(MXSecretStorageKeyCreationInfo * _Nonnull keyCreationInfo) {
            
            // -> privateKeyFromRecoveryKey must return the same private key
            NSError *error;
            NSData *privateKeyFromRecoveryKey = [recoveryService privateKeyFromRecoveryKey:keyCreationInfo.recoveryKey error:&error];
            XCTAssertNil(error);
            XCTAssertEqualObjects(privateKeyFromRecoveryKey, keyCreationInfo.privateKey);
            
            // -> privateKeyFromPassphrase must return the same private key
            [recoveryService privateKeyFromPassphrase:passphrase success:^(NSData * _Nonnull privateKey) {
                
                XCTAssertEqualObjects(privateKey, keyCreationInfo.privateKey);
                
                [expectation fulfill];
            } failure:^(NSError * _Nonnull error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
            
        } failure:^(NSError * _Nonnull error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end
