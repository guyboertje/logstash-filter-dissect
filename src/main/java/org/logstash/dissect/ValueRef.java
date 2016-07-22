package org.logstash.dissect;

import java.nio.charset.StandardCharsets;

final class ValueRef {
    private final int position;
    private final int length;

    ValueRef(int position, int length) {
        this.position = position;
        this.length = length;
    }

    String extract(byte[] source) {
        return new String(source, position, length, StandardCharsets.UTF_8);
    }

    @Override
    public String toString() {
        final StringBuilder sb = new StringBuilder("ValueRef{");
        sb.append("position=").append(position);
        sb.append(", length=").append(length);
        sb.append('}');
        return sb.toString();
    }
}
