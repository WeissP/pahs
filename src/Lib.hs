module Lib where

import MyPrelude
import RIO.ByteString.Lazy qualified as BL
import RIO.List qualified as L
import RIO.NonEmpty qualified as NE
import RIO.Process
import RIO.Text qualified as T

type PassRecordName = String
type PassTag = Text

data PassRecord = PassRecord
  {_prName :: PassRecordName, _prPw :: Text, _prProps :: [(PassTag, Text)]}
  deriving stock (Show)
makeClassy ''PassRecord

data PassEnv = PassEnv {_peLf :: LogFunc, _peCtx :: ProcessContext}
  deriving stock (Generic)
makeClassy ''PassEnv
instance HasProcessContext PassEnv where
  processContextL = peCtx
instance HasLogFunc PassEnv where
  logFuncL = peLf

data PassException = PassException PassRecordName String
instance Show PassException where
  show (PassException name msg) =
    "error during getting password of name " <> show name <> " via Pass: " <> msg
instance Exception PassException

data PassTagNotFound = PassTagNotFound PassRecordName PassTag
instance Show PassTagNotFound where
  show (PassTagNotFound name tag) =
    "could not find tag " <> show tag <> " of Pass record: " <> show name
instance Exception PassTagNotFound

prProp :: (MonadReader env m, HasPassRecord env) => Text -> m (Maybe Text)
prProp key = do
  pr <- view prProps
  return $ L.lookup key pr

prProp_ :: (MonadReader env m, HasPassRecord env, MonadThrow m) => PassTag -> m Text
prProp_ tag = do
  name <- view prName
  pr <- view prProps
  forceJust (L.lookup tag pr) $ PassTagNotFound name tag

getPassRecord ::
  (HasProcessContext env, HasLogFunc env) => String -> RIO env PassRecord
getPassRecord name = proc "pass" [name] $ \pc -> do
  raw <- decodeUtf8Lenient . BL.toStrict <$> readProcessStdout_ pc
  pw :| props <-
    forceJust (NE.nonEmpty $ T.lines raw)
      $ PassException name "got empty pass record"
  let parseProp p = (T.strip k, T.strip $ T.drop 1 v)
        where
          (k, v) = T.break (':' ==) p
  return $ PassRecord name pw (parseProp <$> props)
