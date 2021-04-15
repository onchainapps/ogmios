--  This Source Code Form is subject to the terms of the Mozilla Public
--  License, v. 2.0. If a copy of the MPL was not distributed with this
--  file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE TypeApplications #-}

module Ogmios.Data.Json.Allegra where

import Ogmios.Data.Json.Prelude

import Cardano.Ledger.Crypto
    ( Crypto )
import GHC.Records
    ( getField )
import Ouroboros.Consensus.Cardano.Block
    ( AllegraEra )
import Ouroboros.Consensus.Shelley.Ledger.Block
    ( ShelleyBlock (..) )
import Shelley.Spec.Ledger.BaseTypes
    ( StrictMaybe (..) )

import qualified Ogmios.Data.Json.Shelley as Shelley

import qualified Cardano.Ledger.AuxiliaryData as MA
import qualified Cardano.Ledger.Era as Era
import qualified Cardano.Ledger.ShelleyMA.AuxiliaryData as MA
import qualified Cardano.Ledger.ShelleyMA.Rules.Utxo as MA
import qualified Cardano.Ledger.ShelleyMA.Timelocks as MA
import qualified Cardano.Ledger.ShelleyMA.TxBody as MA
import qualified Shelley.Spec.Ledger.BlockChain as Sh
import qualified Shelley.Spec.Ledger.PParams as Sh
import qualified Shelley.Spec.Ledger.STS.Ledger as Sh
import qualified Shelley.Spec.Ledger.STS.Ledgers as Sh
import qualified Shelley.Spec.Ledger.Tx as Sh
import qualified Shelley.Spec.Ledger.UTxO as Sh

--
-- Encoders
--

encodeAllegraBlock
    :: Crypto crypto
    => SerializationMode
    -> ShelleyBlock (AllegraEra crypto)
    -> Json
encodeAllegraBlock mode (ShelleyBlock (Sh.Block blkHeader txs) headerHash) =
    encodeObject
    [ ( "body"
      , encodeFoldable (encodeTx mode) (Sh.txSeqTxns' txs)
      )
    , ( "header"
      , Shelley.encodeBHeader mode blkHeader
      )
    , ( "headerHash"
      , Shelley.encodeShelleyHash headerHash
      )
    ]

encodeAuxiliaryData
    :: Crypto crypto
    => MA.AuxiliaryData (AllegraEra crypto)
    -> Json
encodeAuxiliaryData (MA.AuxiliaryData blob scripts) = encodeObject
    [ ( "blob"
      , Shelley.encodeMetadataBlob blob
      )
    , ( "scriptPreImages"
      , encodeFoldable encodeTimelock scripts
      )
    ]

encodeLedgerFailure
    :: Crypto crypto
    => Sh.LedgersPredicateFailure (AllegraEra crypto)
    -> Json
encodeLedgerFailure = \case
    Sh.LedgerFailure (Sh.UtxowFailure e)  ->
        Shelley.encodeUtxowFailure encodeUtxoFailure e
    Sh.LedgerFailure (Sh.DelegsFailure e) ->
        Shelley.encodeDelegsFailure e

encodePParams'
    :: (forall a. (a -> Json) -> Sh.HKD f a -> Json)
    -> Sh.PParams' f era
    -> Json
encodePParams' =
    Shelley.encodePParams'

encodeProposedPPUpdates
    :: Sh.ProposedPPUpdates era
    -> Json
encodeProposedPPUpdates =
    Shelley.encodeProposedPPUpdates

encodeTimelock
    :: Crypto crypto
    => MA.Timelock crypto
    -> Json
encodeTimelock = \case
    MA.RequireSignature sig ->
        Shelley.encodeKeyHash sig
    MA.RequireAllOf xs ->
        encodeObject [( "all", encodeFoldable encodeTimelock xs )]
    MA.RequireAnyOf xs ->
        encodeObject [( "any", encodeFoldable encodeTimelock xs )]
    MA.RequireMOf n xs ->
        encodeObject [( show n, encodeFoldable encodeTimelock xs )]
    MA.RequireTimeExpire s ->
        encodeObject [( "expiresAt", encodeSlotNo s )]
    MA.RequireTimeStart s ->
        encodeObject [( "startsAt", encodeSlotNo s )]

encodeTx
    :: Crypto crypto
    => SerializationMode
    -> Sh.Tx (AllegraEra crypto)
    -> Json
encodeTx mode x = encodeObjectWithMode mode
    [ ( "id"
      , Shelley.encodeTxId (Sh.txid (Sh._body x))
      )
    , ( "body"
      , encodeTxBody (Sh._body x)
      )
    , ( "metadata", encodeObject
        [ ( "hash"
          , encodeStrictMaybe Shelley.encodeAuxiliaryDataHash (adHash (Sh._body x))
          )
        , ( "body"
          , encodeStrictMaybe encodeAuxiliaryData (Sh._metadata x)
          )
        ]
      )
    ]
    [ ( "witness"
      , encodeWitnessSet (Sh._witnessSet x)
      )
    ]
  where
    adHash :: MA.TxBody era -> StrictMaybe (MA.AuxiliaryDataHash (Era.Crypto era))
    adHash = getField @"adHash"

encodeTxBody
    :: Crypto crypto
    => MA.TxBody (AllegraEra crypto)
    -> Json
encodeTxBody (MA.TxBody inps outs certs wdrls fee validity updates _ _) = encodeObject
    [ ( "inputs"
      , encodeFoldable Shelley.encodeTxIn inps
      )
    , ( "outputs"
      , encodeFoldable Shelley.encodeTxOut outs
      )
    , ( "certificates"
      , encodeFoldable Shelley.encodeDCert certs
      )
    , ( "withdrawals"
      , Shelley.encodeWdrl wdrls
      )
    , ( "fee"
      , Shelley.encodeCoin fee
      )
    , ( "validityInterval"
      , encodeValidityInterval validity
      )
    , ( "update"
      , encodeStrictMaybe Shelley.encodeUpdate updates
      )
    ]

encodeUtxo
    :: Crypto crypto
    => Sh.UTxO (AllegraEra crypto)
    -> Json
encodeUtxo =
    Shelley.encodeUtxo

encodeUtxoFailure
    :: Crypto crypto
    => MA.UtxoPredicateFailure (AllegraEra crypto)
    -> Json
encodeUtxoFailure = \case
    MA.BadInputsUTxO inputs ->
        encodeObject
            [ ( "badInputs"
              , encodeFoldable Shelley.encodeTxIn inputs
              )
            ]
    MA.OutsideValidityIntervalUTxO itv currentSlot ->
        encodeObject
            [ ( "outsideOfValidityInterval", encodeObject
                [ ( "interval" , encodeValidityInterval itv )
                , ( "currentSlot" , encodeSlotNo currentSlot )
                ]
              )
            ]
    MA.OutputTooBigUTxO outs ->
        encodeObject
            [ ( "outputsTooLarge"
              , encodeFoldable Shelley.encodeTxOut outs
              )
            ]
    MA.MaxTxSizeUTxO actualSize maxSize ->
        encodeObject
            [ ( "txTooLarge", encodeObject
                [ ( "maximumSize", encodeInteger maxSize )
                , ( "actualSize", encodeInteger actualSize )
                ]
              )
            ]
    MA.InputSetEmptyUTxO ->
        encodeText "missingAtLeastOneInputUtxo"
    MA.FeeTooSmallUTxO required actual ->
        encodeObject
            [ ( "feeTooSmall", encodeObject
                [ ( "requiredFee", Shelley.encodeCoin required )
                , ( "actualFee", Shelley.encodeCoin actual )
                ]
              )
            ]
    MA.ValueNotConservedUTxO consumed produced ->
        encodeObject
            [ ( "valueNotConserved", encodeObject
                [ ( "consumed", Shelley.encodeDeltaCoin consumed )
                , ( "produced", Shelley.encodeDeltaCoin produced )
                ]
              )
            ]
    MA.WrongNetwork expected invalidAddrs ->
        encodeObject
            [ ( "networkMismatch", encodeObject
                [ ( "expectedNetwork", Shelley.encodeNetwork expected )
                , ( "invalidAddresses", encodeFoldable Shelley.encodeAddress invalidAddrs )
                ]
              )
            ]
    MA.WrongNetworkWithdrawal expected invalidAccts ->
        encodeObject
            [ ( "networkMismatch", encodeObject
                [ ( "expectedNetwork" , Shelley.encodeNetwork expected )
                , ( "invalidRewardAccounts" , encodeFoldable Shelley.encodeRewardAcnt invalidAccts )
                ]
              )
            ]
    MA.OutputTooSmallUTxO outs ->
        encodeObject
            [ ( "outputTooSmall"
              , encodeFoldable Shelley.encodeTxOut outs
              )
            ]
    MA.OutputBootAddrAttrsTooBig outs ->
        encodeObject
            [ ( "addressAttributesTooLarge"
              , encodeFoldable Shelley.encodeAddress ((\(Sh.TxOut addr _) -> addr) <$> outs)
              )
            ]
    MA.TriesToForgeADA ->
        encodeString "triesToForgeAda"
    MA.UpdateFailure e ->
        Shelley.encodeUpdateFailure e

encodeValidityInterval
    :: MA.ValidityInterval
    -> Json
encodeValidityInterval x = encodeObject
    [ ( "invalidBefore"
      , encodeStrictMaybe encodeSlotNo (MA.invalidBefore x)
      )
    , ( "invalidHereafter"
      , encodeStrictMaybe encodeSlotNo (MA.invalidHereafter x)
      )
    ]

encodeWitnessSet
    :: Crypto crypto
    => Sh.WitnessSet (AllegraEra crypto)
    -> Json
encodeWitnessSet x = encodeObject
    [ ( "address"
      , encodeFoldable Shelley.encodeWitVKey (Sh.addrWits x)
      )
    , ( "script"
      , encodeMap Shelley.stringifyScriptHash encodeTimelock (Sh.scriptWits x)
      )
    , ( "bootstrap"
      , encodeFoldable Shelley.encodeBootstrapWitness (Sh.bootWits x)
      )
    ]