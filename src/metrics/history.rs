use std::collections::VecDeque;

#[derive(Debug, Clone)]
pub struct HistoryBuffer<T> {
    values: VecDeque<T>,
    capacity: usize,
}

impl<T> HistoryBuffer<T> {
    pub fn new(capacity: usize) -> Self {
        Self {
            values: VecDeque::with_capacity(capacity),
            capacity,
        }
    }

    pub fn push(&mut self, value: T) {
        if self.capacity == 0 {
            return;
        }
        if self.values.len() == self.capacity {
            self.values.pop_front();
        }
        self.values.push_back(value);
    }

    #[cfg(test)]
    pub fn len(&self) -> usize {
        self.values.len()
    }

    #[cfg(test)]
    pub fn is_empty(&self) -> bool {
        self.values.is_empty()
    }
}

impl<T: Clone> HistoryBuffer<T> {
    pub fn values(&self) -> Vec<T> {
        self.values.iter().cloned().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::HistoryBuffer;

    #[test]
    fn history_buffer_keeps_only_latest_values() {
        let mut history = HistoryBuffer::new(3);

        history.push(1);
        history.push(2);
        history.push(3);
        history.push(4);

        assert_eq!(history.values(), vec![2, 3, 4]);
        assert_eq!(history.len(), 3);
    }

    #[test]
    fn zero_capacity_history_drops_values() {
        let mut history = HistoryBuffer::new(0);

        history.push(1);

        assert!(history.is_empty());
    }
}
