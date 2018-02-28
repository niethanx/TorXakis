-- | 
{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE DeriveAnyClass    #-}
module TorXakis.Session where

import           Control.Concurrent.STM.TVar    (TVar)
import           Control.DeepSeq                (NFData)
import           GHC.Generics                   (Generic)
import           Lens.Micro                     (Lens')
import           Control.Concurrent.STM.TQueue (TQueue)

import           Sigs     (Sigs, empty)
import           VarId    (VarId)
import           TxsDefs  (TxsDefs, empty)
import           EnvCore  (EnvC, initState)
import           EnvData  (Msg)

-- | The session, which maintains the state of a TorXakis model.
data Session = Session
    { _sessionState :: TVar SessionSt
    , _sessionMsgs  :: TQueue Msg
    }

data SessionSt = SessionSt
    { _tdefs   :: TxsDefs
    , _sigs    :: Sigs VarId
    , _envCore :: EnvC
    } deriving (Generic, NFData)

-- * Session state manipulation
emptySessionState :: SessionSt
emptySessionState = SessionSt TxsDefs.empty Sigs.empty initState

-- * Lenses

sessionState :: Lens' Session (TVar SessionSt)
sessionState h (Session s m) = (`Session` m) <$> h s

sessionMsgs :: Lens' Session (TQueue Msg)
sessionMsgs h (Session s m) = Session s <$> h m

tdefs :: Lens' SessionSt TxsDefs
-- Remember:
--
-- > Lens' s a = forall f. Functor f => (a -> f a) -> s -> f s
-- > h :: (TxsDefs -> f TxsDefs)
-- > x :: SessionSt
tdefs h (SessionSt t s c) = (\t' -> SessionSt t' s c) <$> h t

sigs :: Lens' SessionSt (Sigs VarId)
-- Defining the rest of the lenses is just the same. However we want to avoid
-- depending on template Haskell to scrap the boilerplate.
sigs h (SessionSt t s c) = (\s' -> SessionSt t s' c) <$> h s

envCore :: Lens' SessionSt EnvC
envCore h (SessionSt t s c) = SessionSt t s <$> h c
