pub fn format_binary_bytes(bytes: u64) -> String {
    const KIB: u64 = 1024;
    const MIB: u64 = KIB * 1024;
    const GIB: u64 = MIB * 1024;
    const TIB: u64 = GIB * 1024;

    if bytes >= TIB {
        format!("{:.1} TiB", bytes as f64 / TIB as f64)
    } else if bytes >= GIB {
        format!("{:.1} GiB", bytes as f64 / GIB as f64)
    } else if bytes >= MIB {
        format!("{:.1} MiB", bytes as f64 / MIB as f64)
    } else if bytes >= KIB {
        format!("{:.1} KiB", bytes as f64 / KIB as f64)
    } else {
        format!("{bytes} B")
    }
}

pub fn format_binary_rate(bytes_per_second: u64) -> String {
    format!("{}/s", format_binary_bytes(bytes_per_second))
}

#[cfg(test)]
mod tests {
    use super::{format_binary_bytes, format_binary_rate};

    #[test]
    fn formats_binary_byte_units() {
        assert_eq!(format_binary_bytes(0), "0 B");
        assert_eq!(format_binary_bytes(1), "1 B");
        assert_eq!(format_binary_bytes(1023), "1023 B");
        assert_eq!(format_binary_bytes(1024), "1.0 KiB");
        assert_eq!(format_binary_bytes(1536), "1.5 KiB");
        assert_eq!(format_binary_bytes(1024 * 1024), "1.0 MiB");
        assert_eq!(format_binary_bytes(1024 * 1024 * 1024), "1.0 GiB");
        assert_eq!(format_binary_bytes(1024_u64.pow(4)), "1.0 TiB");
    }

    #[test]
    fn formats_binary_rate_units() {
        assert_eq!(format_binary_rate(512), "512 B/s");
        assert_eq!(format_binary_rate(1024), "1.0 KiB/s");
        assert_eq!(format_binary_rate(1024 * 1024), "1.0 MiB/s");
    }
}
