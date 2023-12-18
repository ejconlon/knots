{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE UndecidableInstances #-}

-- | Some useful fixpoints of Functors and Bifunctors.
module Knots
  ( Base1
  , Recursive1 (..)
  , Corecursive1 (..)
  , cata1
  , cata1M
  , Fix (..)
  , mkFix
  , unMkFix
  , transFix
  , Knot (..)
  , mkKnot
  , unMkKnot
  , transKnot
  , Anno (..)
  , annoUnit
  , annoUnitM
  , annoCounit
  , annoCounitM
  , annoLeft
  , annoLeftM
  , annoRight
  , annoRightM
  , MemoF (..)
  , pattern MemoFP
  , memoFKey
  , memoFVal
  , Memo (..)
  , pattern MemoP
  , mkMemo
  , unMkMemo
  , transMemo
  , memoKey
  , memoVal
  , memoCata
  , memoCataM
  )
where

import Control.Comonad (Comonad (..))
import Control.Monad ((>=>))
import Control.Monad.Reader (Reader, ReaderT (..), runReader)
import Data.Bifoldable (Bifoldable (..))
import Data.Bifunctor (Bifunctor (..))
import Data.Bifunctor.TH (deriveBifoldable, deriveBifunctor, deriveBitraversable)
import Data.Bitraversable (Bitraversable (..))
import Data.Functor.Apply (Apply (..))
import Data.Functor.Foldable (Base, Corecursive (..), Recursive (..))
import Data.Functor.Identity (Identity (..))
import Data.Kind (Type)
import Data.String (IsString)
import Prettyprinter (Pretty)

-- | 'Base' for Bifunctors
type family Base1 (f :: Type -> Type) :: Type -> Type -> Type

-- | 'Recursive' for Bifunctors
class (Bifunctor (Base1 f), Functor f) => Recursive1 f where
  project1 :: f a -> Base1 f a (f a)

-- | 'Corecursive' for Bifunctors
class (Bifunctor (Base1 f), Functor f) => Corecursive1 f where
  embed1 :: Base1 f a (f a) -> f a

-- | 'cata' for Bifunctors
cata1 :: (Recursive1 f, Base1 f ~ g) => (g a b -> b) -> f a -> b
cata1 f = go where go = f . second go . project1

-- | 'cataM' for Bifunctors
cata1M :: (Monad m, Recursive1 f, Base1 f ~ g, Bitraversable g) => (g a b -> m b) -> f a -> m b
cata1M f = go where go = bitraverse pure go . project1 >=> f

fmapViaBi :: (Recursive1 f, Corecursive1 f, Base1 f ~ g) => (a -> b) -> f a -> f b
fmapViaBi f = go where go = embed1 . bimap f go . project1

foldrViaBi :: (Recursive1 f, Base1 f ~ g, Bifoldable g) => (a -> b -> b) -> b -> f a -> b
foldrViaBi f = flip go where go fa b = bifoldr f go b (project1 fa)

traverseViaBi
  :: (Recursive1 f, Corecursive1 f, Base1 f ~ g, Bitraversable g, Applicative m) => (a -> m b) -> f a -> m (f b)
traverseViaBi f = go where go = fmap embed1 . bitraverse f go . project1

-- | A basic Functor fixpoint like you'd see anywhere.
type Fix :: (Type -> Type) -> Type
newtype Fix f = Fix {unFix :: f (Fix f)}

deriving newtype instance (Eq (f (Fix f))) => Eq (Fix f)

deriving newtype instance (Ord (f (Fix f))) => Ord (Fix f)

deriving stock instance (Show (f (Fix f))) => Show (Fix f)

deriving newtype instance (Pretty (f (Fix f))) => Pretty (Fix f)

deriving newtype instance (IsString (f (Fix f))) => IsString (Fix f)

type instance Base (Fix f) = f

instance (Functor f) => Recursive (Fix f) where project = unFix

instance (Functor f) => Corecursive (Fix f) where embed = Fix

-- | Pull a recursive structure apart and retie as a 'Fix'.
mkFix :: (Recursive t, Base t ~ f) => t -> Fix f
mkFix = cata Fix

-- | Go the other way.
unMkFix :: (Corecursive t, Base t ~ f) => Fix f -> t
unMkFix = cata embed

-- | Transform the base Functor.
transFix :: (Functor f) => (forall x. f x -> g x) -> Fix f -> Fix g
transFix nat = go
 where
  go = Fix . nat . fmap go . unFix

-- | A fixpoint for a Bifunctor where the second type variable contains
-- the recursive structure.
type Knot :: (Type -> Type -> Type) -> Type -> Type
newtype Knot g a = Knot {unKnot :: g a (Knot g a)}

deriving newtype instance (Eq (g a (Knot g a))) => Eq (Knot g a)

deriving newtype instance (Ord (g a (Knot g a))) => Ord (Knot g a)

deriving stock instance (Show (g a (Knot g a))) => Show (Knot g a)

deriving newtype instance (Pretty (g a (Knot g a))) => Pretty (Knot g a)

deriving newtype instance (IsString (g a (Knot g a))) => IsString (Knot g a)

type instance Base1 (Knot g) = g

instance (Bifunctor g) => Recursive1 (Knot g) where project1 = unKnot

instance (Bifunctor g) => Corecursive1 (Knot g) where embed1 = Knot

instance (Bifunctor g) => Functor (Knot g) where fmap = fmapViaBi

instance (Bifunctor g, Bifoldable g) => Foldable (Knot g) where foldr = foldrViaBi

instance (Bitraversable g) => Traversable (Knot g) where traverse = traverseViaBi

-- | Pull a recursive structure apart and retie as a 'Knot'.
mkKnot :: (Recursive1 f, Base1 f ~ g) => f a -> Knot g a
mkKnot = cata1 Knot

-- | Go the other way.
unMkKnot :: (Corecursive1 f, Base1 f ~ g) => Knot g a -> f a
unMkKnot = cata1 embed1

-- | Transform the base Bifunctor.
transKnot :: (Bifunctor g) => (forall x y. g x y -> h x y) -> Knot g a -> Knot h a
transKnot nat = go
 where
  go = Knot . nat . second go . unKnot

-- | An "annotation" - a strict key associated with a lazy value.
-- Hopefully this is a bit better behaved than just a tuple, being
-- strict in the head and lazy in the tail when this is tied into a
-- recursive structure.
type Anno :: Type -> Type -> Type
data Anno k v = Anno {annoKey :: !k, annoVal :: v}
  deriving stock (Eq, Ord, Show, Functor, Foldable, Traversable)

deriveBifunctor ''Anno
deriveBifoldable ''Anno
deriveBitraversable ''Anno

instance (Semigroup k) => Apply (Anno k) where
  liftF2 f (Anno k1 v1) (Anno k2 v2) = Anno (k1 <> k2) (f v1 v2)

instance (Monoid k) => Applicative (Anno k) where
  pure = Anno mempty
  liftA2 = liftF2

instance Comonad (Anno k) where
  extract (Anno _ v) = v
  extend f an@(Anno k _) = Anno k (f an)

-- | 'unit' from 'Adjunction'
annoUnit :: v -> Reader k (Anno k v)
annoUnit v = ReaderT (Identity . (`Anno` v))

annoUnitM :: (Applicative m) => v -> ReaderT k m (Anno k v)
annoUnitM v = ReaderT (pure . (`Anno` v))

-- | 'counit' from 'Adjunction'
annoCounit :: Anno k (Reader k v) -> v
annoCounit (Anno k m) = runReader m k

annoCounitM :: Anno k (ReaderT k m v) -> m v
annoCounitM (Anno k m) = runReaderT m k

-- | 'leftAdjunct' from 'Adjunction'
annoLeft :: (Anno k v -> x) -> v -> Reader k x
annoLeft f v = ReaderT (Identity . f . (`Anno` v))

annoLeftM :: (Anno k v -> m x) -> v -> ReaderT k m x
annoLeftM f v = ReaderT (f . (`Anno` v))

-- | 'rightAdjunct' from 'Adjunction'
annoRight :: (v -> Reader k x) -> Anno k v -> x
annoRight f (Anno k v) = runReader (f v) k

annoRightM :: (v -> ReaderT k m x) -> Anno k v -> m x
annoRightM f (Anno k v) = runReaderT (f v) k

-- | The base functor for a 'Memo'
newtype MemoF f k r = MemoF {unMemoF :: Anno k (f r)}
  deriving stock (Show, Functor)
  deriving newtype (Eq, Ord)

pattern MemoFP :: k -> f r -> MemoF f k r
pattern MemoFP k v = MemoF (Anno k v)

{-# COMPLETE MemoFP #-}

instance (Apply f, Semigroup k) => Apply (MemoF f k) where
  liftF2 f (MemoF (Anno k1 v1)) (MemoF (Anno k2 v2)) = MemoF (Anno (k1 <> k2) (liftF2 f v1 v2))

instance (Applicative f, Monoid k) => Applicative (MemoF f k) where
  pure = MemoF . Anno mempty . pure
  liftA2 f (MemoF (Anno k1 v1)) (MemoF (Anno k2 v2)) = MemoF (Anno (k1 <> k2) (liftA2 f v1 v2))

type Memo :: (Type -> Type) -> Type -> Type
newtype Memo f k = Memo {unMemo :: MemoF f k (Memo f k)}

pattern MemoP :: k -> f (Memo f k) -> Memo f k
pattern MemoP k v = Memo (MemoF (Anno k v))

{-# COMPLETE MemoP #-}

memoFKey :: MemoF f k r -> k
memoFKey (MemoFP k _) = k

memoFVal :: MemoF f k r -> f r
memoFVal (MemoFP _ v) = v

deriving stock instance (Eq k, Eq (f (Memo f k))) => Eq (Memo f k)

deriving stock instance (Ord k, Ord (f (Memo f k))) => Ord (Memo f k)

deriving stock instance (Show k, Show (f (Memo f k))) => Show (Memo f k)

instance (Functor f) => Functor (Memo f) where
  fmap f = go where go (MemoP k v) = MemoP (f k) (fmap go v)

instance (Foldable f) => Foldable (Memo f) where
  foldr f = flip go where go (MemoP k v) z = foldr go (f k z) v

instance (Traversable f) => Traversable (Memo f) where
  traverse f = go where go (MemoP k v) = liftA2 MemoP (f k) (traverse go v)

type instance Base (Memo f k) = MemoF f k

instance (Functor f) => Recursive (Memo f k) where project = unMemo

instance (Functor f) => Corecursive (Memo f k) where embed = Memo

-- | Pull a recursive structure apart and retie as a 'Memo', using the given
-- function to calculate a key for every level.
mkMemo :: (Recursive t, Base t ~ f) => (f k -> k) -> t -> Memo f k
mkMemo f = cata (\v -> MemoP (f (fmap memoKey v)) v)

-- | Forget keys at every level and convert back to a plain structure.
unMkMemo :: (Corecursive t, Base t ~ f) => Memo f k -> t
unMkMemo (MemoP _ v) = embed (fmap unMkMemo v)

-- | Transform the base functor.
transMemo :: (Functor f) => (forall x. f x -> g x) -> Memo f k -> Memo g k
transMemo nat = go
 where
  go (MemoP k v) = MemoP k (nat (fmap go v))

memoKey :: Memo f k -> k
memoKey (MemoP k _) = k

memoVal :: Memo f k -> f (Memo f k)
memoVal (MemoP _ v) = v

-- | 'cata' but nicer
memoCata :: (Functor f) => (f x -> Reader k x) -> Memo f k -> x
memoCata f = go
 where
  go (MemoP k v) = runReader (f (fmap go v)) k

-- | 'cataM' but nicer
memoCataM :: (Monad m, Traversable f) => (f x -> ReaderT k m x) -> Memo f k -> m x
memoCataM f = go
 where
  go (MemoP k v) = traverse go v >>= \x -> runReaderT (f x) k
